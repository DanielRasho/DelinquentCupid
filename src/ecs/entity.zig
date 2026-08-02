const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const IComponentStorage = @import("component.zig").IComponentStorage;
const ComponentStorage = @import("component.zig").ComponentStorage;

pub const VOID_ARCHETYPE_HASH = std.math.maxInt(u64);

pub const EntityID = u64;

pub const ArchetypeTable = struct {
    hash: u64,
    allocator: Allocator,
    total_rows: usize,

    entities: std.ArrayList(EntityID) = .empty,
    components: std.array_hash_map.String(IComponentStorage) = .empty,

    pub fn deinit(
        self: *ArchetypeTable,
    ) void {
        for (self.components.values()) |component| {
            component.deinit(self.allocator);
        }
        self.entities.deinit(self.allocator);
        self.components.deinit(self.allocator);
    }
    pub fn calculateHash(self: *ArchetypeTable) void {
        self.hash = 0;
        var iter = self.components.iterator();
        while (iter.next()) |entry| {
            const component_name = entry.key_ptr.*;
            self.hash ^= std.hash_map.hashString(component_name);
        }
    }

    //
    pub fn insert(self: *ArchetypeTable, id: EntityID) !u32 {
        const new_row_index = self.entities.items.len;
        try self.entities.append(self.allocator, id);
        return @intCast(new_row_index);
    }
    pub fn undoInsertion(self: *ArchetypeTable) void {
        self.entities.pop();
    }

    // pub fn set(self: *ArchetypeTable, row_index: u32, component: anytype) !void {
    //     var iStorage = self.components.get(name).?;
    //     var storage = IComponentStorage.cast(iStorage.ptr, @TypeOf(component));
    // }

    pub fn removeEntity() void {}

    pub fn getEntityComponent(self: *ArchetypeTable, comptime Component: type) ComponentStorage(Component) {
        _ = self;
    }
};

pub const EntityDB = struct {
    allocator: Allocator,

    counter: EntityID = 0,

    entities: std.AutoHashMapUnmanaged(EntityID, Pointer) = .empty,

    archetypes: std.array_hash_map.Auto(u64, ArchetypeTable) = .empty,

    pub const Pointer = struct {
        archetype_index: u16,
        row_index: u32,
    };

    pub const Iterator = struct {};

    // ===============
    // PUBLIC API
    // ===============
    pub fn init(allocator: Allocator) !EntityDB {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *EntityDB) void {
        self.entities.deinit(self.allocator);

        var iter = self.archetypes.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.archetypes.deinit(self.allocator);
    }
    pub fn new() void {}
    pub fn remove() void {}
    pub fn setComponent() void {}
    pub fn getComponent(id: EntityID) void {
        _ = id;
    }
    pub fn removeComponent() void {}
    pub fn getArchetypeTable() void {}
    pub fn query(self: *EntityDB, comptime components: anytype) Iterator {
        _ = self;
        _ = components;
    }
};

test "ArchetypeTable - Basic" {
    const allocator = std.testing.allocator;
    var table = ArchetypeTable{
        .allocator = allocator,
        .hash = VOID_ARCHETYPE_HASH,
        .total_rows = 1,
    };
    table.deinit();
}

test "Entity DB - Basic" {
    const allocator = std.testing.allocator;
    _ = allocator;
}
