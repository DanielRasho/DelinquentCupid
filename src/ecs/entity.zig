const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const IComponentStore = @import("component.zig").IComponentStore;
const ComponentStore = @import("component.zig").ComponentStore;
const assert = std.debug.assert;

pub const VOID_ARCHETYPE_HASH = std.math.maxInt(u64);

pub const EntityID = u64;

pub const EntityDBError = error{EntityNotFound};

pub const ArchetypeTable = struct {
    hash: u64,
    allocator: Allocator,

    entities: std.ArrayList(EntityID) = .empty,
    components: std.array_hash_map.String(IComponentStore) = .empty,

    pub fn deinit(
        self: *ArchetypeTable,
    ) void {
        for (self.components.values()) |component| {
            component.deinit(self.allocator);
        }
        self.entities.deinit(self.allocator);
        self.components.deinit(self.allocator);
    }
    pub fn calculateHash(names: []const []const u8) u64 {
        var hash: u64 = 0;
        for (names) |name| {
            hash ^= std.hash_map.hashString(name);
        }
        return hash;
    }

    pub fn hasComponents(self: *const ArchetypeTable, components: []const []const u8) bool {
        for (components) |c| {
            if (!self.components.contains(c))
                return false;
        }
        return true;
    }

    pub fn count(self: *const ArchetypeTable) usize {
        return self.entities.items.len;
    }

    //
    pub fn insert(self: *ArchetypeTable, id: EntityID) !u32 {
        const new_row_index = self.entities.items.len;
        try self.entities.append(self.allocator, id);
        return @intCast(new_row_index);
    }
    pub fn undoInsertion(self: *ArchetypeTable) void {
        _ = self.entities.pop();
    }

    pub fn set(self: *ArchetypeTable, row_index: u32, component_name: []const u8, value: anytype) !void {
        const iStorage = self.components.get(component_name).?;
        var storage = IComponentStore.cast(iStorage.ptr, @TypeOf(value));
        try storage.set(self.allocator, row_index, value);
    }

    pub fn getEntityIdByIdx(self: *const ArchetypeTable, idx: usize) u64 {
        return self.entities.items[idx];
    }

    pub fn removeEntity(self: *ArchetypeTable, row_idx: usize) void {
        for (self.components.values()) |*c| {
            c.remove(row_idx);
        }
        _ = self.entities.swapRemove(row_idx);
    }

    pub fn getIComponentStorage(self: *ArchetypeTable, componentName: []const u8) ?IComponentStore {
        return self.components.get(componentName) orelse return null;
    }
};

pub const EntityDB = struct {
    allocator: Allocator,

    counter: EntityID = 0,

    entities: std.AutoHashMapUnmanaged(EntityID, Pointer) = .empty,

    archetypes: std.array_hash_map.Auto(u64, ArchetypeTable) = .empty,

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

        try entities.archetypes.put(allocator, VOID_ARCHETYPE_HASH, ArchetypeTable{ .allocator = allocator, .hash = VOID_ARCHETYPE_HASH, .components = .empty, .entities = .empty });

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

    pub fn setComponent(self: *EntityDB, entity: EntityID, component: anytype) !void {
        const Component = @TypeOf(component);
        const component_name = @typeName(Component);

        // Get current pointer before any reallocation
        const old_pointer = self.entities.get(entity) orelse return EntityDBError.EntityNotFound;
        const old_archetype_index = old_pointer.archetype_index;

        // Get or create the destination archetype
        // We pass the index, not a pointer, to avoid dangling refs after reallocation
        const new_archetype_index = try self.getOrCreateArchetype(old_archetype_index, Component);

        // If it's the same archetype, component already exists — just overwrite
        if (old_archetype_index == new_archetype_index) {
            const archetype = &self.archetypes.values()[new_archetype_index];
            try archetype.set(old_pointer.row_index, component_name, component);
            return;
        }

        const new_archetype = &self.archetypes.values()[new_archetype_index];

        // Insert entity into new archetype row
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
        try new_archetype.set(new_row, component_name, component);

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

        var src_entries = try self.snapshotColumns(src_index, null);
        defer src_entries.deinit(self.allocator);

        const result = try self.getOrCreateArchetypeForHash(new_hash, src_entries.items);
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

    // Finds or creates the archetype reached from src_index by dropping component_name.
    fn getOrCreateArchetypeWithout(
        self: *EntityDB,
        src_index: u16,
        component_name: []const u8,
    ) !u16 {
        const src_hash = self.archetypes.values()[src_index].hash;
        const new_hash = src_hash ^ std.hash_map.hashString(component_name);

        var src_entries = try self.snapshotColumns(src_index, component_name);
        defer src_entries.deinit(self.allocator);

        const result = try self.getOrCreateArchetypeForHash(new_hash, src_entries.items);
        return result.index;
    }

    const ColumnEntry = struct { key: []const u8, value: IComponentStore };

    // Snapshots the component columns of an archetype, optionally skipping one by name.
    // Must be taken before touching self.archetypes, since inserting into it can reallocate.
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

    // Finds the archetype with the given hash, or creates one populated with the given columns.
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

    // removes and entity and all its components.
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

    // removes a component from an entity by moving it to another ArchetypeTable, if it doesn't exist it creates it
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

    pub fn getComponent(self: *EntityDB, id: EntityID, comptime Component: type) ?*Component {
        const ptr = self.entities.get(id).?;
        const archetype = self.getEntityArchetype(id) orelse return null;

        const iStore = archetype.getIComponentStorage(@typeName(Component)) orelse return null;
        const store = IComponentStore.cast(iStore.ptr, Component);

        return store.getPtr(ptr.row_index);
    }

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

test "ArchetypeTable - Basic" {
    const allocator = std.testing.allocator;
    var table = ArchetypeTable{
        .allocator = allocator,
        .hash = VOID_ARCHETYPE_HASH,
    };
    table.deinit();
}

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
