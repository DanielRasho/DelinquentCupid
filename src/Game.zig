const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const ecs = @import("ecs");

const Scene = ecs.scene.Scene;

// The Game: owns the scenes and switches between them. There is exactly
// one Game, so it's a plain module (comptime-cached by @import), not a
// struct you instantiate -- same reasoning as Scene owning one EntityDB.
//
// Nobody switches scenes directly from inside a system. To change scenes, a
// system spawns a SwitchRequest entity into its own scene:
//
//   const id = try scn.entities.new();
//   try scn.entities.setComponent(id, Game.SwitchRequest{ .to = "gameover" });
//
// and the Game honors it AFTER the frame's update() returns -- never in the
// middle of one, while the current scene's systems are still iterating the
// very EntityDB a switch would tear down. Deferred transitions like this
// are how real engines avoid that whole class of crashes.
//
// Calling switchTo()/start() directly (from main.zig, or from a debug tool
// window) is fine: those run outside any system's update, so there's no
// iterator left dangling.

/// Builds a fresh Scene for `name`: registers whichever systems that scene
/// needs and returns it, not yet set up (Game calls `.setup()` itself).
/// Factories are called fresh on every visit, so no stale state can survive
/// leaving a scene and coming back to it.
pub const SceneFactory = *const fn (allocator: Allocator) anyerror!Scene;

/// Spawn one of these into the current scene to request a switch. `to` must
/// outlive the switch (a string literal is fine); the entity carrying it,
/// and the scene it lives in, is torn down as part of performing it.
pub const SwitchRequest = struct { to: []const u8 };

var allocator: Allocator = undefined;
var factories: std.array_hash_map.String(SceneFactory) = .empty;
var current: ?Scene = null;
var current_name: ?[]const u8 = null;

/// Must be called once, before registering any scene.
pub fn init(alloc: Allocator) void {
    allocator = alloc;
}

/// Tears down the current scene (if any) and frees the factory registry.
pub fn deinit() void {
    if (current) |*scn| {
        scn.destroy();
        scn.deinit();
        current = null;
    }
    factories.deinit(allocator);
    factories = .empty;
    current_name = null;
}

/// Registers a scene factory under `name`. Scenes register a factory, not
/// an instance -- see `SceneFactory`.
pub fn registerScene(name: []const u8, factory: SceneFactory) !void {
    try factories.put(allocator, name, factory);
}

fn performSwitch(name: []const u8) !void {
    const factory = factories.get(name) orelse return error.UnknownScene;
    if (current) |*scn| {
        scn.destroy();
        scn.deinit();
    }
    current = try factory(allocator);
    current_name = name;
    if (current) |*scn| scn.setup();
}

/// Enters `name` as the very first scene. Call once, after registering.
pub fn start(name: []const u8) !void {
    try performSwitch(name);
}

/// Switches to `name` right away. Safe to call from outside a system's
/// update (main.zig, a debug tool, ...) -- see the module doc comment above
/// for why systems should prefer spawning a `SwitchRequest` instead.
pub fn switchTo(name: []const u8) !void {
    try performSwitch(name);
}

pub fn update(dt: f32) void {
    const scn = if (current) |*s| s else return;
    scn.update(dt);

    // The frame is over now, so it's safe to honor a switch request.
    var it = scn.entities.query(.{SwitchRequest});
    if (it.next()) |id| {
        const req = scn.entities.getComponent(id, SwitchRequest).?;
        switchTo(req.to) catch |err| {
            std.log.err("scene switch to '{s}' failed: {}", .{ req.to, err });
        };
    }
}

pub fn render() void {
    if (current) |*scn| scn.render();
}

/// The scene currently running, or null before `start()`.
pub fn currentScene() ?*Scene {
    return if (current) |*scn| scn else null;
}

/// The name of the scene currently running, or null before `start()`.
pub fn currentName() ?[]const u8 {
    return current_name;
}

/// Every registered scene name, sorted, caller-owned. Game code never needs
/// this -- it always knows where it's going. It exists for TOOLS, same
/// story as EntityDB.query() being usable from outside a system: a debug
/// scene switcher asks "where could we go?" without hardcoding a list.
pub fn sceneNames(alloc: Allocator) ![][]const u8 {
    const names = try alloc.dupe([]const u8, factories.keys());
    std.mem.sort([]const u8, names, {}, lessThanStr);
    return names;
}

fn lessThanStr(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

test "Game - registers, starts and switches scenes" {
    const alloc = testing.allocator;
    init(alloc);
    defer deinit();

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

    try registerScene("menu", Scenes.menu);
    try registerScene("gameplay", Scenes.gameplay);

    // sceneNames() is sorted, for debug tooling to enumerate.
    const names = try sceneNames(alloc);
    defer alloc.free(names);
    try testing.expectEqualSlices(u8, "gameplay", names[0]);
    try testing.expectEqualSlices(u8, "menu", names[1]);

    // start() enters the first scene and runs its setup.
    try start("menu");
    try testing.expectEqualStrings("menu", currentName().?);

    // A system requests a switch by spawning a SwitchRequest entity; the
    // Game only honors it once update() has moved past the scene's own
    // systems for this frame.
    {
        const scn = currentScene().?;
        const id = try scn.entities.new();
        try scn.entities.setComponent(id, SwitchRequest{ .to = "gameplay" });
    }
    update(0.016);
    try testing.expectEqualStrings("gameplay", currentName().?);

    // Switching away tore the old scene down and built a fresh one -- no
    // leftover SwitchRequest, no leftover menu Marker.
    var leftover_requests = currentScene().?.entities.query(.{SwitchRequest});
    try testing.expect(leftover_requests.next() == null);

    // switchTo() works directly too, e.g. from a debug tool button.
    try switchTo("menu");
    try testing.expectEqualStrings("menu", currentName().?);

    // Unknown scene names fail loudly instead of silently no-op-ing.
    try testing.expectError(error.UnknownScene, switchTo("does-not-exist"));
}
