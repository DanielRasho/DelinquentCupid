const std = @import("std");
const ecs = @import("ecs");
const constants = @import("../constants.zig");
const comps = @import("../components.zig");
const field = @import("../field.zig");

const Sys = ecs.system.System;
const Scene = ecs.scene.Scene;

// ===================
// PLAYER
// ===================
pub const player_system = Sys{ .setup = playerSetup, .update = playerUpdate, .destroy = playerDestroy };

fn playerSetup(_: *Sys, scn: *Scene) void {
    spawnPlayer(scn) catch |err| std.debug.panic("player setup failed: {}", .{err});
}
fn spawnPlayer(scn: *Scene) !void {
    const id = try scn.entities.new();
    try scn.entities.setComponent(id, comps.Player{});
    try scn.entities.setComponent(id, comps.Position{
        .x = constants.FIELD_LEFT + constants.FIELD_W / 2.0,
        .y = constants.FIELD_BOTTOM + 4 + constants.PLAYER_SIZE / 2.0,
    });
}
fn playerDestroy(_: *Sys, scn: *Scene) void {
    var it = scn.entities.query(.{comps.Player});
    if (it.next()) |id| scn.entities.remove(id);
}

/// Once the volley is over, the player walks to where its first ball landed:
/// that's where the next turn is fired from.
fn playerUpdate(_: *Sys, scn: *Scene, _: f32) void {
    var game_it = scn.entities.query(.{comps.Turn});
    const turn = scn.entities.getComponent(game_it.next().?, comps.Turn).?;
    if (turn.phase == .FIRING) return;

    var it = scn.entities.query(.{ comps.Player, comps.Position });
    const id = it.next() orelse return;
    const player = scn.entities.getComponent(id, comps.Player).?;
    if (!player.landed) return;

    scn.entities.getComponent(id, comps.Position).?.x = field.clampToFloor(player.next_x);
    player.landed = false;
}
