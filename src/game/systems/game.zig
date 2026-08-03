const std = @import("std");
const ecs = @import("ecs");
const comps = @import("../components.zig");

const Sys = ecs.system.System;
const Scene = ecs.scene.Scene;

// ===================
// GAME (singleton)
// ===================
pub const game_system = Sys{ .setup = gameSetup, .destroy = gameDestroy };

fn gameSetup(_: *Sys, scn: *Scene) void {
    spawnGame(scn) catch |err| std.debug.panic("game setup failed: {}", .{err});
}
fn spawnGame(scn: *Scene) !void {
    const id = try scn.entities.new();
    try scn.entities.setComponent(id, comps.GameStatus{ .status = .READY });
    try scn.entities.setComponent(id, comps.Lives{ .count = 3 });
    try scn.entities.setComponent(id, comps.Score{ .broken = 0, .total = 0 });
}
fn gameDestroy(_: *Sys, scn: *Scene) void {
    var it = scn.entities.query(.{comps.GameStatus});
    if (it.next()) |id| scn.entities.remove(id);
}
