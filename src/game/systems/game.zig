const std = @import("std");
const ecs = @import("ecs");
const constants = @import("../constants.zig");
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
    try scn.entities.setComponent(id, comps.Turn{ .phase = .AIMING, .wave = 1 });
    try scn.entities.setComponent(id, comps.Volley{});
    try scn.entities.setComponent(id, comps.BallStock{ .normal = constants.STARTING_BALLS });
    try scn.entities.setComponent(id, comps.LovePoints{});
    try scn.entities.setComponent(id, comps.Spirit{});
    try scn.entities.setComponent(id, comps.Upgrades{});
    try scn.entities.setComponent(id, comps.TarotDraw{});
    try scn.entities.setComponent(id, comps.Combo{});
}
fn gameDestroy(_: *Sys, scn: *Scene) void {
    var it = scn.entities.query(.{comps.Turn});
    if (it.next()) |id| scn.entities.remove(id);

    var req_it = scn.entities.query(.{Game.SwitchRequest});
    if (req_it.next()) |id| scn.entities.remove(id);
}

/// The block system only *flags* the run as lost or won; this hands over to
/// the matching scene. The switch goes through a `SwitchRequest` entity so the Game
/// only applies it after every system finished this frame.
fn gameUpdate(_: *Sys, scn: *Scene, _: f32) void {
    var it = scn.entities.query(.{comps.Turn});
    const turn = scn.entities.getComponent(it.next().?, comps.Turn).?;
    const target: []const u8 = switch (turn.phase) {
        .LOST => constants.SCENE_LOSE,
        .WON => constants.SCENE_WIN,
        else => return,
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
