const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

pub const entity = @import("entity.zig");
pub const component = @import("component.zig");
pub const system = @import("systems.zig");
pub const scene = @import("scene.zig");
pub const reflect = @import("reflect.zig");

const Scene = scene.Scene;

/// A Game is Singleton with a collection of scenes and utility functions to change between them.
/// A Scene represents a set of assets/systems that are meant to work together.
pub const Game = struct {
    /// Each scene is related to a SceneFactory function.
    /// It contains the code responsable to instantiate/initialize such Scene.
    /// A `constructor` method if you may.
    pub const SceneFactory = *const fn (allocator: Allocator) anyerror!Scene;

    /// A component meant to ask for switching between scenes.
    /// The Game checks after each frame for the prescense of entities with this component
    /// If detected, it launches the switch after the current frame is fully completed.
    pub const SwitchRequest = struct { to: []const u8 };

    // Singleton
    pub var instance: Game = .{};

    allocator: Allocator = undefined,
    factories: std.array_hash_map.String(SceneFactory) = .empty,
    current: ?Scene = null,
    current_name: ?[]const u8 = null,

    /// Must be called once, before registering any scene.
    pub fn init(self: *Game, alloc: Allocator) void {
        self.* = .{ .allocator = alloc };
    }

    /// Tears down the current scene (if any) and frees the factory registry.
    pub fn deinit(self: *Game) void {
        if (self.current) |*scn| {
            scn.destroy();
            scn.deinit();
            self.current = null;
        }
        self.factories.deinit(self.allocator);
        self.factories = .empty;
        self.current_name = null;
    }

    /// Registers a scene factory under `name`. Scenes register a factory, not
    /// an instance -- see `SceneFactory`.
    pub fn registerScene(self: *Game, name: []const u8, factory: SceneFactory) !void {
        try self.factories.put(self.allocator, name, factory);
    }

    fn performSwitch(self: *Game, name: []const u8) !void {
        const factory = self.factories.get(name) orelse return error.UnknownScene;
        if (self.current) |*scn| {
            scn.destroy();
            scn.deinit();
        }
        self.current = try factory(self.allocator);
        self.current_name = name;
        if (self.current) |*scn| scn.setup();
    }

    /// Enters `name` as the very first scene. Call once, after registering.
    pub fn start(self: *Game, name: []const u8) !void {
        try self.performSwitch(name);
    }

    /// Switches to a given scene right away. Safe to call from outside a system's
    /// update. But systems withing the ECS should prefer spawning SwitchRequest objects.
    pub fn switchTo(self: *Game, name: []const u8) !void {
        try self.performSwitch(name);
    }

    pub fn update(self: *Game, dt: f32) void {
        const scn = if (self.current) |*s| s else return;
        scn.update(dt);

        // The frame is over now, so it's safe to honor a switch request.
        var it = scn.entities.query(.{SwitchRequest});
        if (it.next()) |id| {
            const req = scn.entities.getComponent(id, SwitchRequest).?;
            self.switchTo(req.to) catch |err| {
                std.log.err("scene switch to '{s}' failed: {}", .{ req.to, err });
            };
        }
    }

    pub fn render(self: *Game) void {
        if (self.current) |*scn| scn.render();
    }

    /// The scene currently running, or null before `start()`.
    pub fn currentScene(self: *Game) ?*Scene {
        return if (self.current) |*scn| scn else null;
    }

    /// The name of the scene currently running, or null before `start()`.
    pub fn currentName(self: *Game) ?[]const u8 {
        return self.current_name;
    }

    // Returns a list of the registered scenes. Useful for debugging tools.
    pub fn sceneNames(self: *Game, alloc: Allocator) ![][]const u8 {
        const names = try alloc.dupe([]const u8, self.factories.keys());
        std.mem.sort([]const u8, names, {}, lessThanStr);
        return names;
    }

    fn lessThanStr(_: void, a: []const u8, b: []const u8) bool {
        return std.mem.lessThan(u8, a, b);
    }
};

test "Game - registers, starts and switches scenes" {
    const alloc = testing.allocator;
    // A local Game rather than `Game.instance`: the test then can't leak
    // state into (or out of) any other test that touches the singleton.
    var game: Game = .{};
    game.init(alloc);
    defer game.deinit();

    const Marker = struct { name: []const u8 };

    const Scenes = struct {
        fn menu(a: Allocator) !Scene {
            var scn = try Scene.init(a);
            const id = try scn.entities.new();
            try scn.entities.setComponent(id, Marker{ .name = "menu" });
            return scn;
        }
        fn gameplay(a: Allocator) !Scene {
            var scn = try Scene.init(a);
            const id = try scn.entities.new();
            try scn.entities.setComponent(id, Marker{ .name = "gameplay" });
            return scn;
        }
    };

    try game.registerScene("menu", Scenes.menu);
    try game.registerScene("gameplay", Scenes.gameplay);

    // sceneNames() is sorted, for debug tooling to enumerate.
    const names = try game.sceneNames(alloc);
    defer alloc.free(names);
    try testing.expectEqualSlices(u8, "gameplay", names[0]);
    try testing.expectEqualSlices(u8, "menu", names[1]);

    // start() enters the first scene and runs its setup.
    try game.start("menu");
    try testing.expectEqualStrings("menu", game.currentName().?);

    // A system requests a switch by spawning a SwitchRequest entity; the
    // Game only honors it once update() has moved past the scene's own
    // systems for this frame.
    {
        const scn = game.currentScene().?;
        const id = try scn.entities.new();
        try scn.entities.setComponent(id, Game.SwitchRequest{ .to = "gameplay" });
    }
    game.update(0.016);
    try testing.expectEqualStrings("gameplay", game.currentName().?);

    // Switching away tore the old scene down and built a fresh one -- no
    // leftover SwitchRequest, no leftover menu Marker.
    var leftover_requests = game.currentScene().?.entities.query(.{Game.SwitchRequest});
    try testing.expect(leftover_requests.next() == null);

    // switchTo() works directly too, e.g. from a debug tool button.
    try game.switchTo("menu");
    try testing.expectEqualStrings("menu", game.currentName().?);

    // Unknown scene names fail loudly instead of silently no-op-ing.
    try testing.expectError(error.UnknownScene, game.switchTo("does-not-exist"));
}

test "ecs - single scene tests" {
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
