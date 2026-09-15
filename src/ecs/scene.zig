const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const entity = @import("entity.zig");
const system = @import("systems.zig");

/// Representation of a set of systems and entities that work together.
pub const Scene = struct {
    allocator: Allocator,
    systems: std.array_hash_map.String(system.System) = .empty,
    entities: entity.EntityDB,

    pub fn init(allocator: Allocator) !Scene {
        return .{
            .allocator = allocator,
            .entities = try entity.EntityDB.init(allocator),
        };
    }
    pub fn deinit(self: *Scene) void {
        self.systems.deinit(self.allocator);
        self.entities.deinit();
    }

    pub fn register(self: *Scene, name: []const u8, s: system.System) !void {
        try self.systems.put(self.allocator, name, s);
    }

    pub fn unregister(self: *Scene, name: []const u8) void {
        self.systems.orderedRemove(name);
    }

    pub fn setup(self: *Scene) void {
        for (self.systems.values()) |*s| {
            s.setup(s, self);
        }
    }
    pub fn update(self: *Scene, dt: f32) void {
        for (self.systems.values()) |*s| {
            if (!s.enabled) continue;
            s.update(s, self, dt);
        }
    }
    pub fn render(self: *Scene) void {
        for (self.systems.values()) |*s| {
            s.render(s, self);
        }
    }
    pub fn destroy(self: *Scene) void {
        for (self.systems.values()) |*s| {
            s.destroy(s, self);
        }
    }
};

test "Scene - Basic" {
    const allocator = std.testing.allocator;
    // Create Scene
    var testing_scene = try Scene.init(allocator);
    defer testing_scene.deinit();

    // Create System
    const testing_system = system.System{
        .update = struct {
            fn call(_: *system.System, _: *Scene, _: f32) void {
                std.log.info("HELLO WORLD\n\n", .{});
            }
        }.call,
    };

    // Add system
    try testing_scene.register("Testing System", testing_system);

    // Run all systems
    testing_scene.update(1);
    // Destroy Scene
    testing_scene.destroy();
}

test "Scene - disabled system skips update but still renders" {
    const allocator = std.testing.allocator;
    var testing_scene = try Scene.init(allocator);
    defer testing_scene.deinit();

    const Counter = struct {
        var updates: usize = 0;
        var renders: usize = 0;
        fn update(_: *system.System, _: *Scene, _: f32) void {
            updates += 1;
        }
        fn render(_: *system.System, _: *Scene) void {
            renders += 1;
        }
    };
    try testing_scene.register("Counter", .{ .update = Counter.update, .render = Counter.render });

    testing_scene.update(1);
    testing_scene.render();
    try testing.expectEqual(@as(usize, 1), Counter.updates);
    try testing.expectEqual(@as(usize, 1), Counter.renders);

    testing_scene.systems.getPtr("Counter").?.enabled = false;
    testing_scene.update(1);
    testing_scene.render();
    try testing.expectEqual(@as(usize, 1), Counter.updates);
    try testing.expectEqual(@as(usize, 2), Counter.renders);
}
