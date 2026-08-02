const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

pub const entity = @import("entity.zig");
pub const component = @import("component.zig");
pub const system = @import("systems.zig");
pub const scene = @import("scene.zig");

test "ecs" {
    _ = entity;
    _ = component;
    _ = system;
    _ = scene;
}
