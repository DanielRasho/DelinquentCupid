const std = @import("std");
const Allocator = std.mem.Allocator;

pub const ComponentStorageError = error{
    // Returned when client wants to set the value of and index
    // that will lead 'empty wholes' in the storage.
    IndexNotTighlyPackaged,
};

/// Generic representation of 'Table Column' in the ECS Database
/// This is done so the database can have columns of multiple types.
pub const IComponentStorage = struct {
    ptr: *anyopaque,

    deinitFn: *const fn (ptr: *anyopaque, allocator: Allocator) void,
    removeFn: *const fn (ptr: *anyopaque, row: u32) void,
    copyFn: *const fn (
        dst_ptr: *anyopaque,
        allocator: Allocator,
        src_row: u32,
        dst_row: u32,
        src_ptr: *anyopaque,
    ) (Allocator.Error || ComponentStorageError)!void,

    /// Cleanups the data stored in the underlying store.
    pub fn deinit(self: IComponentStorage, allocator: Allocator) void {
        self.deinitFn(self.ptr, allocator);
    }

    /// Removes a component at a given idx from the storage
    pub fn remove(self: IComponentStorage, row: u32) void {
        self.removeFn(self.ptr, row);
    }

    /// Copies one component from a source storage to the current one
    pub fn copy(
        self: IComponentStorage,
        allocator: Allocator,
        src_row: u32,
        dst_row: u32,
        src: IComponentStorage,
    ) !void {
        try self.copyFn(self.ptr, allocator, src_row, dst_row, src.ptr);
    }

    /// Cast a IComponentStorage to an asked type.
    pub fn cast(ptr: *anyopaque, comptime Component: type) *ComponentStorage(Component) {
        return @ptrCast(@alignCast(ptr));
    }
};

/// A concrete Column Type that stores Components of a certain type
/// in an arraylist and provides methods to interact with them.
pub fn ComponentStorage(comptime Component: type) type {
    return struct {
        const Self = @This();

        /// Reference to the total number of Components this Storage has.
        /// Managed by the user.
        total_rows: *usize,

        /// Arraylist containing each of the components
        data: std.ArrayList(Component) = .empty,

        /// Cleanups the data stored in a component storage
        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.data.deinit(allocator);
        }
        /// Sets/overwrites the values at a given storage index,
        /// should address a existent space, or one higher that the max current lenght
        /// to ensure dense data.
        pub fn set(self: *Self, allocator: Allocator, row_idx: u32, component: Component) !void {
            if (row_idx > self.count()) {
                return ComponentStorageError.IndexNotTighlyPackaged;
            } else if (row_idx == self.count()) {
                // Since row_idx == len, only one element is needed.
                try self.data.append(allocator, undefined);
            }

            self.data.items[row_idx] = component;
        }
        /// Returns a component at a given idx
        pub fn get(self: *Self, row_idx: u32) Component {
            return self.data.items[row_idx];
        }
        /// Removes a component at a given idx from the storage
        pub fn remove(self: *Self, row_idx: u32) void {
            if (row_idx < self.count()) {
                _ = self.data.swapRemove(row_idx);
            }
        }
        /// Copies one component from a source storage to the current one
        pub fn copyFrom(self: *Self, allocator: Allocator, src_row: u32, dst_row: u32, src: *Self) !void {
            try self.set(allocator, dst_row, src.get(src_row));
        }
        inline fn count(self: *Self) usize {
            return self.data.items.len;
        }

        // -------------------------------------------------
        // Type erasure
        // -------------------------------------------------

        pub fn interface(self: *Self) IComponentStorage {
            return .{
                .ptr = self,
                .deinitFn = deinitErased,
                .removeFn = removeErased,
                .copyFn = copyErased,
            };
        }

        fn deinitErased(ptr: *anyopaque, allocator: Allocator) void {
            const storage = IComponentStorage.cast(ptr, Component);
            storage.deinit(allocator);
        }

        fn removeErased(ptr: *anyopaque, row: u32) void {
            const storage = IComponentStorage.cast(ptr, Component);
            storage.remove(row);
        }

        fn copyErased(dst_ptr: *anyopaque, allocator: Allocator, src_row: u32, dst_row: u32, src_ptr: *anyopaque) !void {
            const dst = IComponentStorage.cast(dst_ptr, Component);
            const src = IComponentStorage.cast(src_ptr, Component);

            try dst.copyFrom(allocator, src_row, dst_row, src);
        }
    };
}

test "ComponentStorage - Basic" {
    const allocator = std.testing.allocator;

    const Cat = struct {
        name: []const u8,
    };

    var total_rows: usize = 2;

    // Creating the Cat Component
    const my_cat = Cat{ .name = "neko" };
    const other_cat = Cat{ .name = "kirito" };

    // Creating Storage
    var storage = ComponentStorage(Cat){ .total_rows = &total_rows };
    var other_storage = ComponentStorage(Cat){ .total_rows = &total_rows };

    // Defering Cleanup
    defer storage.deinit(allocator);
    defer other_storage.deinit(allocator);

    // Inserting Components
    try storage.set(allocator, 0, my_cat);
    try storage.set(allocator, 1, other_cat);
    try other_storage.set(allocator, 0, my_cat);

    // Copy component from one store to the other
    try storage.copyFrom(allocator, 0, 0, &other_storage);

    // Removing comopnent
    storage.remove(0);
}

test "IComponentStorage - Basic" {
    const allocator = std.testing.allocator;

    const Cat = struct {
        name: []const u8,
    };

    var total_rows: usize = 1;

    const my_cat = Cat{ .name = "neko" };

    var storage = ComponentStorage(Cat){ .total_rows = &total_rows };

    try storage.set(allocator, 0, my_cat);

    // Creating interface object
    const erased = storage.interface();
    // Interacting with the concrete object through the interface
    defer erased.deinit(allocator);
    erased.remove(0);
}
