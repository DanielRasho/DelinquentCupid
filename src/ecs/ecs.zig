const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

pub const entity = @import("entity.zig");
pub const component = @import("component.zig");
pub const system = @import("systems.zig");
pub const scene = @import("scene.zig");

test "ecs - integration" {
    const allocator = std.testing.allocator;

    const Position = struct { x: f32, y: f32 };
    const Velocity = struct { x: f32, y: f32 };
    const Movable = struct {};

    const MovementSystem = struct {
        var spawned: entity.EntityID = undefined;
        var setup_calls: usize = 0;
        var render_calls: usize = 0;
        var destroy_calls: usize = 0;

        fn setup(_: *system.System, scn: *scene.Scene) void {
            setup_calls += 1;
            spawned = scn.entities.new() catch unreachable;
            scn.entities.setComponent(spawned, Position{ .x = 0, .y = 0 }) catch unreachable;
            scn.entities.setComponent(spawned, Velocity{ .x = 1, .y = 2 }) catch unreachable;
            scn.entities.setComponent(spawned, Movable{}) catch unreachable;
        }

        fn update(_: *system.System, scn: *scene.Scene, dt: f32) void {
            var it = scn.entities.query(.{ Movable, Position, Velocity });
            while (it.next()) |id| {
                const pos = scn.entities.getComponent(id, Position).?;
                const vel = scn.entities.getComponent(id, Velocity).?;
                pos.x += vel.x * dt;
                pos.y += vel.y * dt;
            }
        }

        fn render(_: *system.System, _: *scene.Scene) void {
            render_calls += 1;
        }

        fn destroy(_: *system.System, scn: *scene.Scene) void {
            destroy_calls += 1;
            scn.entities.remove(spawned);
        }
    };

    var world = try scene.Scene.init(allocator);
    defer world.deinit();

    try world.register("Movement", system.System{
        .setup = MovementSystem.setup,
        .update = MovementSystem.update,
        .render = MovementSystem.render,
        .destroy = MovementSystem.destroy,
    });

    // setup() spawns the entity
    world.setup();
    try testing.expectEqual(@as(usize, 1), MovementSystem.setup_calls);

    // update() moves it by velocity * dt
    world.update(2.0);
    const pos = world.entities.getComponent(MovementSystem.spawned, Position).?;
    try testing.expectEqual(@as(f32, 2.0), pos.x);
    try testing.expectEqual(@as(f32, 4.0), pos.y);

    // render() runs, driven by the Scene rather than called directly
    world.render();
    try testing.expectEqual(@as(usize, 1), MovementSystem.render_calls);

    // Dropping Velocity moves the entity to a new archetype; it should stop moving
    try world.entities.removeComponent(MovementSystem.spawned, Velocity);
    world.update(1.0);
    const pos_after = world.entities.getComponent(MovementSystem.spawned, Position).?;
    try testing.expectEqual(@as(f32, 2.0), pos_after.x);
    try testing.expect(world.entities.getComponent(MovementSystem.spawned, Velocity) == null);

    // destroy() tears the entity back down
    world.destroy();
    try testing.expectEqual(@as(usize, 1), MovementSystem.destroy_calls);
    try testing.expect(!world.entities.entities.contains(MovementSystem.spawned));
}
