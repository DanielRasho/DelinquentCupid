const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs");
const constants = @import("../constants.zig");
const comps = @import("../components.zig");
const terrain = @import("../terrain.zig");

const Sys = ecs.system.System;
const Scene = ecs.scene.Scene;

// ===================
// MAP: the stage's background, a trail of soil between grass (`terrain.zig`).
// Spawns it, and scrolls it one row down whenever the blocks descend.
// `render.zig` draws it, under everything else, sliding it by the same
// `Descent.lag` as the blocks.
//
// Registered after `Block`: the descent `block.zig` starts on a frame is
// already flagged here that same frame, so the map is drawn scrolled from
// the descent's first frame on.
// ===================
pub const map_system = Sys{ .setup = mapSetup, .update = mapUpdate, .destroy = mapDestroy };

fn mapSetup(_: *Sys, scn: *Scene) void {
    spawnMap(scn) catch |err| std.debug.panic("map setup failed: {}", .{err});
}
fn spawnMap(scn: *Scene) !void {
    const id = try scn.entities.new();
    try scn.entities.setComponent(id, comps.Terrain{ .cells = terrain.generate(random(), constants.MAP_GRASS_CHANCE) });
}
fn mapDestroy(_: *Sys, scn: *Scene) void {
    var it = scn.entities.query(.{comps.Terrain});
    if (it.next()) |id| scn.entities.remove(id);
}

/// One row down (and a fresh one on top) per descent, on its first frame.
fn mapUpdate(_: *Sys, scn: *Scene, _: f32) void {
    var map_it = scn.entities.query(.{comps.Terrain});
    const map = scn.entities.getComponent(map_it.next() orelse return, comps.Terrain).?;
    var game_it = scn.entities.query(.{comps.Descent});
    const descent = scn.entities.getComponent(game_it.next().?, comps.Descent).?;

    if (!descent.started) {
        map.scrolled = false;
        return;
    }
    if (map.scrolled) return;
    terrain.scroll(&map.cells, random(), constants.MAP_GRASS_CHANCE);
    map.scrolled = true;
}

/// A `std.Random` drawing from raylib's generator, the one the rest of the
/// game rolls with (so seeding raylib seeds the map too).
fn random() std.Random {
    return .{ .ptr = undefined, .fillFn = fillFromRaylib };
}
fn fillFromRaylib(_: *anyopaque, buf: []u8) void {
    for (buf) |*byte| byte.* = @intCast(rl.getRandomValue(0, 255));
}
