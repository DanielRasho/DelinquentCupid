const std = @import("std");
const Allocator = std.mem.Allocator;
const IComponentStore = @import("component.zig").IComponentStore;

pub const VOID_ARCHETYPE_HASH = std.math.maxInt(u64);

pub const EntityID = u64;
pub const ArchetypeTableHash = u64;

/// A group of entities that share the exact same set of component types,
/// stored as a set of dense, tightly-packed columns (one `IComponentStore`
/// per component type) plus a parallel `entities` column mapping row index
/// to `EntityID`. Owned and indexed by `EntityDB`.
pub const ArchetypeTable = struct {
    hash: ArchetypeTableHash,
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

    pub fn insert(self: *ArchetypeTable, id: EntityID) !u32 {
        const new_row_index = self.entities.items.len;
        try self.entities.append(self.allocator, id);
        return @intCast(new_row_index);
    }
    pub fn undoInsertion(self: *ArchetypeTable) void {
        _ = self.entities.pop();
    }

    pub fn setComponent(self: *ArchetypeTable, row_index: u32, component_name: []const u8, value: anytype) !void {
        const iStorage = self.components.get(component_name).?;
        var storage = IComponentStore.cast(iStorage.ptr, @TypeOf(value));
        try storage.set(self.allocator, row_index, value);
    }

    pub fn getEntityIdByIdx(self: *const ArchetypeTable, idx: usize) u64 {
        return self.entities.items[idx];
    }

    pub fn removeEntity(self: *ArchetypeTable, row_idx: usize) void {
        // Since all columns are in the same order, a swap remove on each one
        // will act as a swapRemove on a complete row, keeping data integrity.
        for (self.components.values()) |*c| {
            c.swapRemove(row_idx);
        }
        _ = self.entities.swapRemove(row_idx);
    }

    pub fn getIComponentStorage(self: *ArchetypeTable, componentName: []const u8) ?IComponentStore {
        return self.components.get(componentName) orelse return null;
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
