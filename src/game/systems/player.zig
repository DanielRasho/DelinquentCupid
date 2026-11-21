const std = @import("std");
const ecs = @import("ecs");
const constants = @import("../constants.zig");
const comps = @import("../components.zig");
const field = @import("../field.zig");
const ease = @import("../ease.zig");

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

/// Once the volley is over, the player walks to where its first ball landed,
/// easing in and out over `PLAYER_WALK_TIME`: that's where the next turn is
/// fired from (the aim system waits for the walk to end).
fn playerUpdate(_: *Sys, scn: *Scene, dt: f32) void {
    var game_it = scn.entities.query(.{comps.Turn});
    const turn = scn.entities.getComponent(game_it.next().?, comps.Turn).?;
    if (turn.phase == .FIRING) return;

    var it = scn.entities.query(.{ comps.Player, comps.Position });
    const id = it.next() orelse return;
    const player = scn.entities.getComponent(id, comps.Player).?;
    const pos = scn.entities.getComponent(id, comps.Position).?;

    if (player.landed) {
        player.landed = false;
        player.next_x = field.clampToFloor(player.next_x);
        // Landing right where it stands: nothing to walk.
        if (@abs(player.next_x - pos.x) < 1) {
            pos.x = player.next_x;
            return;
        }
        player.walking = true;
        player.walk_from = pos.x;
        player.walk_time = 0;
    }
    if (!player.walking) return;

    player.walk_time += dt;
    const t = @min(player.walk_time / constants.PLAYER_WALK_TIME, 1.0);
    pos.x = player.walk_from + (player.next_x - player.walk_from) * ease.inOutCubic(t);
    if (t >= 1.0) player.walking = false;
}
