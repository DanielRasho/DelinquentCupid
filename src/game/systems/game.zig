const std = @import("std");
const ecs = @import("ecs");
const constants = @import("constants.zig");
const comps = @import("../components.zig");

const Sys = ecs.system.System;
const Scene = ecs.scene.Scene;
const Game = ecs.Game;

// ===================
// GAME (singleton)
// ===================
pub const game_system = Sys{ .setup = gameSetup, .update = gameUpdate, .destroy = gameDestroy };

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

    var req_it = scn.entities.query(.{Game.SwitchRequest});
    if (req_it.next()) |id| scn.entities.remove(id);
}

/// Once the round is decided (ball/brick systems flip the status), hand over
/// to the matching end scene. The switch goes through a `SwitchRequest`
/// entity so the Game only applies it after every system finished this frame.
fn gameUpdate(_: *Sys, scn: *Scene, _: f32) void {
    var it = scn.entities.query(.{comps.GameStatus});
    const status = scn.entities.getComponent(it.next().?, comps.GameStatus).?;
    const target: []const u8 = switch (status.status) {
        .WIN => constants.SCENE_WIN,
        .LOOSE => constants.SCENE_LOSE,
        .READY, .PLAYING => return,
    };

    // Only ever one request in flight.
    var pending = scn.entities.query(.{Game.SwitchRequest});
    if (pending.next() != null) return;

    requestSwitch(scn, target) catch |err| std.debug.panic("game switch request failed: {}", .{err});
}
fn requestSwitch(scn: *Scene, to: []const u8) !void {
    const id = try scn.entities.new();
    try scn.entities.setComponent(id, Game.SwitchRequest{ .to = to });
}
