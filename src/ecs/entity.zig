const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const ErasedComponentStorage = @import("component.zig").IComponent;
const ComponentStorage = @import("component.zig").ComponentStorage;

pub const void_archetype_hash = std.math.maxInt(u64);
pub const EntityID = u64;
