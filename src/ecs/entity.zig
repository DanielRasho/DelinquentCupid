const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const assert = std.debug.assert;

const IComponentStore = @import("component.zig").IComponentStore;
const ComponentStore = @import("component.zig").ComponentStore;

const reflect = @import("reflect.zig");
const archetype_table = @import("archetype_table.zig");
pub const ArchetypeTable = archetype_table.ArchetypeTable;
pub const VOID_ARCHETYPE_HASH = archetype_table.VOID_ARCHETYPE_HASH;
pub const EntityID = archetype_table.EntityID;
pub const ArchetypeTableHash = archetype_table.ArchetypeTableHash;

pub const EntityDBError = error{EntityNotFound};

/// The Entity Database, responsable of managing the creation of entities and
/// its componentes. Relying in maintaing a dictionary of ArchetypTables.
/// The Tables and rows are created automatically on demand.
pub const EntityDB = struct {
    allocator: Allocator,

    counter: EntityID = 0,

    entities: std.AutoHashMapUnmanaged(EntityID, Pointer) = .empty,

    archetypes: std.array_hash_map.Auto(ArchetypeTableHash, ArchetypeTable) = .empty,

    // ===============
    // PUBLIC TYPES
    // ===============
    pub const Pointer = struct {
        archetype_index: u16,
        row_index: u32,
    };

    pub const Iterator = struct {
        entities: *EntityDB,
        components: []const []const u8,
        archetype_idx: usize = 0,
        entity_idx: usize = 0,

        pub fn next(self: *Iterator) ?EntityID {
            const db = self.entities;

            while (true) {
                if (self.archetype_idx >= db.countArchetypes()) return null;

                const archetype = db.getArchetypeTableByIndex(self.archetype_idx);

                // Skip void archetype and empty archetypes
                // Asking for entities with no properties is useless.
                const is_void = archetype.hash == VOID_ARCHETYPE_HASH;
                const has_match = !is_void and
                    archetype.hasComponents(self.components) and
                    self.entity_idx < archetype.count();

                if (has_match) {
                    const id = archetype.getEntityIdByIdx(self.entity_idx);
                    self.entity_idx += 1;
                    return id;
                }

                self.archetype_idx += 1;
                self.entity_idx = 0;
            }
        }
    };

    // ===============
    // PUBLIC API
    // ===============
    pub fn init(allocator: Allocator) !EntityDB {
        var entities = EntityDB{ .allocator = allocator };

        try entities.archetypes.put(allocator, VOID_ARCHETYPE_HASH, ArchetypeTable{
            .allocator = allocator,
            .hash = VOID_ARCHETYPE_HASH,
            .components = .empty,
            .entities = .empty,
        });

        return entities;
    }

    pub fn deinit(self: *EntityDB) void {
        var iter = self.archetypes.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.entities.deinit(self.allocator);
        self.archetypes.deinit(self.allocator);
    }

    /// Creates a new entity without any component so it is assigned to the VOID ARCHETYPE
    /// (a table with no components);
    pub fn new(self: *EntityDB) !EntityID {
        const new_id = self.counter;
        self.counter += 1;

        var void_archetype = self.archetypes.getPtr(VOID_ARCHETYPE_HASH).?;
        const new_row = try void_archetype.insert(new_id);
        const void_pointer = Pointer{
            .archetype_index = 0, // void archetype is guaranteed to be first index
            .row_index = new_row,
        };

        self.entities.put(self.allocator, new_id, void_pointer) catch |err| {
            void_archetype.undoInsertion();
            return err;
        };
        return new_id;
    }

    /// Adds/updates a component to an entity.
    ///
    /// The actual implementation moves the component across tables if the entity didn't have
    /// the component previously to mantain the data thighly packaged.
    ///
    /// If a table with such combination of components didnt' exist is it created.
    pub fn setComponent(self: *EntityDB, entity: EntityID, component: anytype) !void {
        const ComponentType = @TypeOf(component);
        const component_name = @typeName(ComponentType);

        // Get current pointer before any reallocation
        const old_pointer = self.entities.get(entity) orelse return EntityDBError.EntityNotFound;
        const old_archetype_index = old_pointer.archetype_index;

        // Get or create the destination archetype
        // We pass the index, not a pointer, to avoid dangling refs after reallocation
        const new_archetype_index = try self.getOrCreateArchetype(old_archetype_index, ComponentType);

        // If it's the same archetype, component already exists — just overwrite
        if (old_archetype_index == new_archetype_index) {
            const archetype = &self.archetypes.values()[new_archetype_index];
            try archetype.setComponent(old_pointer.row_index, component_name, component);
            return;
        }

        const new_archetype = &self.archetypes.values()[new_archetype_index];

        // Insert entity id into new archetype row
        const new_row = try new_archetype.insert(entity);
        errdefer new_archetype.undoInsertion();

        // Copy all existing components from old archetype to new archetype
        const old_archetype = &self.archetypes.values()[old_archetype_index];
        var col_iter = old_archetype.components.iterator();
        while (col_iter.next()) |col| {
            const dst_store = new_archetype.components.getPtr(col.key_ptr.*) orelse continue;
            try dst_store.copy(self.allocator, old_pointer.row_index, new_row, col.value_ptr.*);
        }

        // Set the new component value
        try new_archetype.setComponent(new_row, component_name, component);

        // Update entity pointer
        try self.entities.put(self.allocator, entity, Pointer{
            .archetype_index = @intCast(new_archetype_index),
            .row_index = new_row,
        });

        // Read the last entity id BEFORE swapRemove moves it
        const last_idx = old_archetype.count() - 1;
        const swapped_entity_id = old_archetype.getEntityIdByIdx(last_idx);

        // Remove entity from old archetype
        old_archetype.removeEntity(old_pointer.row_index);

        // swapRemove moves the last element into old_pointer.row_index
        // only fix up the pointer if they are different entities
        if (swapped_entity_id != entity) {
            if (self.entities.getPtr(swapped_entity_id)) |swapped_ptr| {
                swapped_ptr.row_index = old_pointer.row_index;
            }
        }
    }

    pub fn getOrCreateArchetype(
        self: *EntityDB,
        src_index: u16,
        comptime Component: type,
    ) !u16 {
        const component_name = @typeName(Component);

        // If component already exists in src archetype, return same index
        if (self.archetypes.values()[src_index].hasComponents(&.{component_name})) {
            return src_index;
        }

        const src_hash = self.archetypes.values()[src_index].hash;
        const new_hash = src_hash ^ std.hash_map.hashString(component_name);

        var src_columns = try self.snapshotColumns(src_index, null);
        defer src_columns.deinit(self.allocator);

        const result = try self.getOrCreateArchetypeForHash(new_hash, src_columns.items);
        if (result.is_new) {
            const new_archetype = &self.archetypes.values()[result.index];
            const total_rows = &new_archetype.entities.items.len;

            // Add the new component column
            const new_store = ComponentStore(Component).cloneEmpty(self.allocator, total_rows) catch |err| {
                assert(self.archetypes.swapRemove(new_hash));
                return err;
            };
            new_archetype.components.put(self.allocator, component_name, new_store) catch |err| {
                assert(self.archetypes.swapRemove(new_hash));
                return err;
            };
        }

        return result.index;
    }

    /// Finds or creates the archetype reached from src_index by dropping component_name.
    fn getOrCreateArchetypeWithout(
        self: *EntityDB,
        src_index: u16,
        component_name: []const u8,
    ) !u16 {
        const src_hash = self.archetypes.values()[src_index].hash;
        // Applying XOR again, produces a hash without the component_name;
        const new_hash = src_hash ^ std.hash_map.hashString(component_name);

        var src_columns = try self.snapshotColumns(src_index, component_name);
        defer src_columns.deinit(self.allocator);

        const result = try self.getOrCreateArchetypeForHash(new_hash, src_columns.items);
        return result.index;
    }

    const ColumnEntry = struct { key: []const u8, value: IComponentStore };

    /// User is owner is the owner of the value.
    /// Snapshots the component columns of an archetype, optionally skipping one by name.
    /// Must be taken before touching self.archetypes, since inserting into it can reallocate values, hence
    /// invalidating pointers.
    fn snapshotColumns(self: *EntityDB, src_index: u16, exclude_name: ?[]const u8) !std.ArrayList(ColumnEntry) {
        var entries: std.ArrayList(ColumnEntry) = .empty;
        errdefer entries.deinit(self.allocator);

        var col_iter = self.archetypes.values()[src_index].components.iterator();
        while (col_iter.next()) |c| {
            if (exclude_name) |name| {
                if (std.mem.eql(u8, c.key_ptr.*, name)) continue;
            }
            try entries.append(self.allocator, .{ .key = c.key_ptr.*, .value = c.value_ptr.* });
        }

        return entries;
    }

    /// Finds the archetype with the given hash, or creates one populated with the given columns.
    fn getOrCreateArchetypeForHash(
        self: *EntityDB,
        new_hash: u64,
        columns: []const ColumnEntry,
    ) !struct { index: u16, is_new: bool } {
        const archetype_entry = try self.archetypes.getOrPut(self.allocator, new_hash);
        if (archetype_entry.found_existing) {
            return .{ .index = @intCast(archetype_entry.index), .is_new = false };
        }

        archetype_entry.value_ptr.* = ArchetypeTable{
            .hash = new_hash,
            .allocator = self.allocator,
        };
        const new_archetype = archetype_entry.value_ptr;
        const total_rows = &new_archetype.entities.items.len;

        for (columns) |entry| {
            const erased = entry.value.cloneEmpty(self.allocator, total_rows) catch |err| {
                assert(self.archetypes.swapRemove(new_hash));
                return err;
            };
            new_archetype.components.put(self.allocator, entry.key, erased) catch |err| {
                assert(self.archetypes.swapRemove(new_hash));
                return err;
            };
        }

        return .{ .index = @intCast(archetype_entry.index), .is_new = true };
    }

    /// removes and entity and all its components.
    pub fn remove(self: *EntityDB, entity: EntityID) void {
        const pointer = self.entities.get(entity) orelse return;
        const archetype = &self.archetypes.values()[pointer.archetype_index];

        // Read the last entity id BEFORE swapRemove moves it
        const last_idx = archetype.count() - 1;
        const swapped_entity_id = archetype.getEntityIdByIdx(last_idx);

        archetype.removeEntity(pointer.row_index);

        // swapRemove moves the last element into pointer.row_index
        // only fix up the pointer if they are different entities
        if (swapped_entity_id != entity) {
            if (self.entities.getPtr(swapped_entity_id)) |swapped_ptr| {
                swapped_ptr.row_index = pointer.row_index;
            }
        }

        _ = self.entities.remove(entity);
    }

    /// removes a component from an entity by moving it to another ArchetypeTable, if it doesn't exist it creates it
    pub fn removeComponent(self: *EntityDB, entity: EntityID, comptime Component: type) !void {
        const component_name = @typeName(Component);

        // Get current pointer before any reallocation
        const old_pointer = self.entities.get(entity) orelse return EntityDBError.EntityNotFound;
        const old_archetype_index = old_pointer.archetype_index;

        // Nothing to do if the entity doesn't have this component
        if (!self.archetypes.values()[old_archetype_index].hasComponents(&.{component_name})) {
            return;
        }

        const new_archetype_index = try self.getOrCreateArchetypeWithout(old_archetype_index, component_name);

        const new_archetype = &self.archetypes.values()[new_archetype_index];

        // Insert entity into new archetype row
        const new_row = try new_archetype.insert(entity);
        errdefer new_archetype.undoInsertion();

        // Copy all remaining components from old archetype to new archetype
        const old_archetype = &self.archetypes.values()[old_archetype_index];
        var col_iter = new_archetype.components.iterator();
        while (col_iter.next()) |col| {
            const src_store = old_archetype.components.getPtr(col.key_ptr.*) orelse continue;
            try col.value_ptr.copy(self.allocator, old_pointer.row_index, new_row, src_store.*);
        }

        // Update entity pointer
        try self.entities.put(self.allocator, entity, Pointer{
            .archetype_index = @intCast(new_archetype_index),
            .row_index = new_row,
        });

        // Read the last entity id BEFORE swapRemove moves it
        const last_idx = old_archetype.count() - 1;
        const swapped_entity_id = old_archetype.getEntityIdByIdx(last_idx);

        // Remove entity from old archetype
        old_archetype.removeEntity(old_pointer.row_index);

        // swapRemove moves the last element into old_pointer.row_index
        // only fix up the pointer if they are different entities
        if (swapped_entity_id != entity) {
            if (self.entities.getPtr(swapped_entity_id)) |swapped_ptr| {
                swapped_ptr.row_index = old_pointer.row_index;
            }
        }
    }

    /// Returns a pointer the a component for the client to modify
    pub fn getComponent(self: *EntityDB, id: EntityID, comptime Component: type) ?*Component {
        const ptr = self.entities.get(id) orelse return null;
        const archetype = self.getEntityArchetype(id) orelse return null;

        const iStore = archetype.getIComponentStorage(@typeName(Component)) orelse return null;
        const store = IComponentStore.cast(iStore.ptr, Component);

        return store.getPtr(ptr.row_index);
    }

    /// Returns a iterator of entityId with given components
    pub fn query(self: *EntityDB, comptime components: anytype) Iterator {
        const component_names = comptime blk: {
            var names: [components.len][]const u8 = undefined;
            for (components, 0..) |T, i| {
                if (@TypeOf(T) != type) {
                    @compileError("query only accepts types, got: " ++ @typeName(@TypeOf(T)));
                }
                names[i] = @typeName(T);
            }
            const result = names;
            break :blk result;
        };

        return Iterator{
            .entities = self,
            .components = &component_names,
        };
    }
    // ===================
    //  DEBUGGING
    // ===================

    /// Useful for tools (an inspector, a debugger) that want to know what's on an
    /// entity without knowing its component types up front; see
    /// `componentsOf` to also *read and write* those components' fields
    /// without their types.
    pub fn getComponentNames(self: *EntityDB, id: EntityID) ?[]const []const u8 {
        const archetype = self.getEntityArchetype(id) orelse return null;
        return archetype.components.keys();
    }

    /// To support debugging tools is necesary to store the type of each component
    /// after compilation.
    ///
    /// Only valid until the next structural change to the database -- any
    /// `new`, `setComponent` or `remove`..., on *any* entity,
    /// can move rows between archetypes and reallocate columns.
    pub const ComponentView = struct {
        /// The full @typeName, i.e. the archetype column key.
        name: []const u8,
        desc: *const reflect.TypeDescriptor,
        /// Exactly `desc.size` bytes; empty for a tag component.
        bytes: []u8,
    };

    /// Walks every component on one entity. Order is the archetype's column
    /// order, which is stable for a given archetype but isn't sorted.
    pub const ComponentIterator = struct {
        archetype: *ArchetypeTable,
        row: u32,
        index: usize = 0,

        pub fn next(self: *ComponentIterator) ?ComponentView {
            const keys = self.archetype.components.keys();
            const stores = self.archetype.components.values();

            while (self.index < keys.len) {
                const i = self.index;
                self.index += 1;

                const bytes = stores[i].rowBytes(self.row) orelse continue; // If row not found, just skip to the next one
                return .{ .name = keys[i], .desc = stores[i].desc, .bytes = bytes };
            }
            return null;
        }
    };

    /// Iterator over all of an entity's components as raw bytes + layout.
    /// Null if the entity doesn't exist.
    pub fn componentsOf(self: *EntityDB, id: EntityID) ?ComponentIterator {
        const pointer = self.entities.get(id) orelse return null;
        return .{
            .archetype = &self.archetypes.values()[pointer.archetype_index],
            .row = pointer.row_index,
        };
    }

    /// One component by its storage key (a full @typeName). Null if the
    /// entity doesn't exist or doesn't have that component.
    pub fn getComponentView(self: *EntityDB, id: EntityID, name: []const u8) ?ComponentView {
        const pointer = self.entities.get(id) orelse return null;
        const archetype = &self.archetypes.values()[pointer.archetype_index];
        const store = archetype.getIComponentStorage(name) orelse return null;
        return .{
            .name = name,
            .desc = store.desc,
            .bytes = store.rowBytes(pointer.row_index) orelse return null,
        };
    }

    // ===============
    // UTILS
    // ===============
    fn countArchetypes(self: *EntityDB) usize {
        return self.archetypes.count();
    }

    fn getEntityArchetype(self: *EntityDB, id: EntityID) ?*ArchetypeTable {
        const pointer = self.entities.get(id) orelse return null;
        return &self.archetypes.values()[pointer.archetype_index];
    }

    fn getArchetypeTableByIndex(self: *const EntityDB, idx: usize) *const ArchetypeTable {
        return &self.archetypes.values()[idx];
    }
};

test "EntityDB - Public API" {
    const allocator = std.testing.allocator;

    const Position = struct {
        x: f32,
        y: f32,
    };

    const Velocity = struct {
        x: f32,
        y: f32,
    };

    var db = try EntityDB.init(allocator);
    defer db.deinit();

    // ----------------------------------------------------
    // Create entities
    // ----------------------------------------------------

    const e1 = try db.new();
    const e2 = try db.new();
    const e3 = try db.new();
    assert(db.entities.size == 3);

    // ----------------------------------------------------
    // Add components
    // ----------------------------------------------------

    try db.setComponent(e1, Position{
        .x = 10,
        .y = 20,
    });

    try db.setComponent(e1, Velocity{
        .x = 1,
        .y = 2,
    });

    try db.setComponent(e2, Position{
        .x = 30,
        .y = 40,
    });

    try db.setComponent(e3, Velocity{
        .x = 3,
        .y = 4,
    });

    // ----------------------------------------------------
    // Read components
    // ----------------------------------------------------

    const pos = db.getComponent(e1, Position).?;
    try std.testing.expectEqual(@as(f32, 10), pos.x);
    try std.testing.expectEqual(@as(f32, 20), pos.y);

    const vel = db.getComponent(e1, Velocity).?;
    try std.testing.expectEqual(@as(f32, 1), vel.x);
    try std.testing.expectEqual(@as(f32, 2), vel.y);

    try std.testing.expect(db.getComponent(e2, Velocity) == null);

    // ----------------------------------------------------
    // Query Position
    // ----------------------------------------------------

    {
        var it = db.query(.{Position});

        var count: usize = 0;

        while (it.next()) |entity| {
            _ = entity;
            count += 1;
        }

        try std.testing.expectEqual(@as(usize, 2), count);
    }

    // ----------------------------------------------------
    // Query Position + Velocity
    // ----------------------------------------------------

    {
        var it = db.query(.{
            Position,
            Velocity,
        });

        var count: usize = 0;

        while (it.next()) |entity| {
            _ = entity;
            count += 1;
        }

        try std.testing.expectEqual(@as(usize, 1), count);
    }

    // ----------------------------------------------------
    // Remove component
    // ----------------------------------------------------

    try db.removeComponent(e1, Velocity);

    try std.testing.expect(db.getComponent(e1, Velocity) == null);

    const pos_after_remove = db.getComponent(e1, Position).?;
    try std.testing.expectEqual(@as(f32, 10), pos_after_remove.x);
    try std.testing.expectEqual(@as(f32, 20), pos_after_remove.y);

    {
        var it = db.query(.{Velocity});

        var count: usize = 0;

        while (it.next()) |entity| {
            try std.testing.expectEqual(e3, entity);
            count += 1;
        }

        try std.testing.expectEqual(@as(usize, 1), count);
    }

    // ----------------------------------------------------
    // Remove entity
    // ----------------------------------------------------

    db.remove(e2);

    try std.testing.expect(!db.entities.contains(e2));

    // ----------------------------------------------------
    // Query again after removals
    // ----------------------------------------------------

    {
        var it = db.query(.{Position});

        var count: usize = 0;

        while (it.next()) |entity| {
            try std.testing.expectEqual(e1, entity);
            count += 1;
        }

        try std.testing.expectEqual(@as(usize, 1), count);
    }
}

/// Finds a view by component type in an iterator, for tests that don't care
/// about archetype column order.
fn findView(db: *EntityDB, id: EntityID, comptime Component: type) ?EntityDB.ComponentView {
    var it = db.componentsOf(id) orelse return null;
    while (it.next()) |view| {
        if (std.mem.eql(u8, view.name, @typeName(Component))) return view;
    }
    return null;
}

test "EntityDB - component views" {
    const allocator = std.testing.allocator;

    const Position = struct { x: f32, y: f32 };
    const Tag = struct {};

    var db = try EntityDB.init(allocator);
    defer db.deinit();

    const e = try db.new();
    try db.setComponent(e, Position{ .x = 3, .y = 4 });
    try db.setComponent(e, Tag{});

    // Every component shows up, keyed by its full @typeName, carrying the
    // same descriptor reflect.zig hands out for that type.
    var seen: usize = 0;
    var it = db.componentsOf(e).?;
    while (it.next()) |_| seen += 1;
    try std.testing.expectEqual(@as(usize, 2), seen);

    const pos_view = findView(&db, e, Position).?;
    try std.testing.expectEqual(reflect.describe(Position), pos_view.desc);
    try std.testing.expectEqualStrings("Position", pos_view.desc.short_name);
    try std.testing.expectEqual(@as(usize, @sizeOf(Position)), pos_view.bytes.len);

    // A tag has a row, it just has no bytes and no fields.
    const tag_view = findView(&db, e, Tag).?;
    try std.testing.expectEqual(@as(usize, 0), tag_view.bytes.len);
    try std.testing.expectEqual(@as(usize, 0), tag_view.desc.fields.len);

    // The bytes alias the real column: writing through a descriptor thunk is
    // visible via the typed accessor.
    const x = pos_view.desc.fields[0];
    try std.testing.expectEqualStrings("x", x.name);
    try std.testing.expectEqual(@as(f64, 3), x.kind.float.load(x.bytes(pos_view.bytes)));

    x.kind.float.store(x.bytes(pos_view.bytes), 99.5);
    try std.testing.expectEqual(@as(f32, 99.5), db.getComponent(e, Position).?.x);
    try std.testing.expectEqual(@as(f32, 4), db.getComponent(e, Position).?.y);
}

test "EntityDB - views survive archetype migration" {
    const allocator = std.testing.allocator;

    const Position = struct { x: f32, y: f32 };
    const Velocity = struct { x: f32, y: f32 };

    var db = try EntityDB.init(allocator);
    defer db.deinit();

    const a = try db.new();
    const b = try db.new();
    try db.setComponent(a, Position{ .x = 1, .y = 1 });
    try db.setComponent(b, Position{ .x = 2, .y = 2 });

    // Moves `a` to a new archetype, which also swap-removes it out of the
    // old one and shifts `b`'s row.
    try db.setComponent(a, Velocity{ .x = 10, .y = 10 });

    // Both entities still resolve to their own rows...
    const a_pos = findView(&db, a, Position).?;
    const b_pos = findView(&db, b, Position).?;
    const ax = a_pos.desc.fields[0];
    try std.testing.expectEqual(@as(f64, 1), ax.kind.float.load(ax.bytes(a_pos.bytes)));
    try std.testing.expectEqual(@as(f64, 2), ax.kind.float.load(ax.bytes(b_pos.bytes)));

    // ... and the descriptor is still the same static one, proving the new
    // archetype's column rebuilt its metadata from the same component type.
    try std.testing.expectEqual(reflect.describe(Position), a_pos.desc);
    try std.testing.expectEqual(reflect.describe(Position), b_pos.desc);
    try std.testing.expectEqual(reflect.describe(Velocity), findView(&db, a, Velocity).?.desc);
}

test "EntityDB - same short name, different modules" {
    const allocator = std.testing.allocator;

    // Two distinct components whose short names collide. Matching on the
    // short name would confuse these; views never match by name at all.
    const A = struct {
        pub const P = struct { x: f32 };
    };
    const B = struct {
        pub const P = struct { flag: bool };
    };

    var db = try EntityDB.init(allocator);
    defer db.deinit();

    const e = try db.new();
    try db.setComponent(e, A.P{ .x = 7 });
    try db.setComponent(e, B.P{ .flag = true });

    const a_view = findView(&db, e, A.P).?;
    const b_view = findView(&db, e, B.P).?;

    try std.testing.expect(!std.mem.eql(u8, a_view.name, b_view.name));
    try std.testing.expectEqualStrings("P", a_view.desc.short_name);
    try std.testing.expectEqualStrings("P", b_view.desc.short_name);

    // Each renders its own fields, not the other's.
    try std.testing.expectEqualStrings("x", a_view.desc.fields[0].name);
    try std.testing.expectEqualStrings("flag", b_view.desc.fields[0].name);
}

test "EntityDB - getComponentView" {
    const allocator = std.testing.allocator;

    const Position = struct { x: f32, y: f32 };

    var db = try EntityDB.init(allocator);
    defer db.deinit();

    const e = try db.new();
    try db.setComponent(e, Position{ .x = 5, .y = 6 });

    try std.testing.expect(db.getComponentView(e, @typeName(Position)) != null);
    // A component the entity doesn't have, and an entity that doesn't exist,
    // are both misses rather than panics.
    try std.testing.expectEqual(@as(?EntityDB.ComponentView, null), db.getComponentView(e, "nope"));
    try std.testing.expectEqual(@as(?EntityDB.ComponentView, null), db.getComponentView(9999, @typeName(Position)));
    try std.testing.expectEqual(@as(?EntityDB.ComponentIterator, null), db.componentsOf(9999));
    try std.testing.expectEqual(@as(?*Position, null), db.getComponent(9999, Position));
}
