const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs");
const constants = @import("../constants.zig");
const ui = @import("../ui.zig");
const sprites = @import("../sprites.zig");

const Sys = ecs.system.System;
const Scene = ecs.scene.Scene;
const Game = ecs.Game;

// ===================
// MAIN MENU: background, the logo up top, and a blinking prompt.
// ===================
pub const menu_system = Sys{ .update = menuUpdate, .render = menuRender, .destroy = menuDestroy };

const BACKGROUND = rl.Rectangle{ .x = 0, .y = 0, .width = constants.SCREEN_W, .height = constants.SCREEN_H };
/// Where the logo goes (its 260 x 120 art at `PIXEL_SCALE`). Shared with the
/// victory and lose screens, so it sits in the same spot on all three.
pub const LOGO = rl.Rectangle{ .x = (constants.SCREEN_W - 520) / 2.0, .y = 90, .width = 520, .height = 240 };
pub const PROMPT_Y: f32 = constants.SCREEN_H - 120;

fn menuUpdate(_: *Sys, scn: *Scene, _: f32) void {
    if (!rl.isKeyPressed(.space)) return;
    // Only ever one request in flight.
    var pending = scn.entities.query(.{Game.SwitchRequest});
    if (pending.next() != null) return;
    requestGame(scn) catch |err| std.debug.panic("menu start failed: {}", .{err});
}
fn requestGame(scn: *Scene) !void {
    const id = try scn.entities.new();
    try scn.entities.setComponent(id, Game.SwitchRequest{ .to = constants.SCENE_GAME });
}
fn menuDestroy(_: *Sys, scn: *Scene) void {
    var it = scn.entities.query(.{Game.SwitchRequest});
    if (it.next()) |id| scn.entities.remove(id);
}

fn menuRender(_: *Sys, _: *Scene) void {
    ui.placeholder(BACKGROUND, "", rl.Color.init(70, 60, 90, 255));
    ui.text("BACKGROUND IMAGE", 16, constants.SCREEN_H - 36, 20, rl.fade(.ray_white, 0.5));
    sprites.drawCentered(.logo, LOGO);
    if (ui.blink()) ui.textCentered("Press SPACE to Start", constants.SCREEN_W / 2.0, PROMPT_Y, 32, .ray_white);
}
