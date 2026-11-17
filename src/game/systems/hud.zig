const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs");
const constants = @import("../constants.zig");
const comps = @import("../components.zig");

const Sys = ecs.system.System;
const Scene = ecs.scene.Scene;

// ===================
// HUD: the wave (turn) counter above the field.
// ===================
pub const hud_system = Sys{ .render = hudRender };

const WAVE_FONT_SIZE: i32 = 32;
const WAVE_Y: i32 = 14;

fn hudRender(_: *Sys, scn: *Scene) void {
    var game_it = scn.entities.query(.{comps.Turn});
    const turn = scn.entities.getComponent(game_it.next() orelse return, comps.Turn).?;

    var buf: [32]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buf, "WAVE {d}", .{turn.wave}) catch "WAVE ?";
    const screen_w: i32 = @intFromFloat(constants.SCREEN_W);
    const x = @divTrunc(screen_w - rl.measureText(text, WAVE_FONT_SIZE), 2);
    rl.drawText(text, x, WAVE_Y, WAVE_FONT_SIZE, .ray_white);
}
