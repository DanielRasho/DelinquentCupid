const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs");
const constants = @import("../constants.zig");
const comps = @import("../components.zig");
const ui = @import("../ui.zig");
const sprites = @import("../sprites.zig");
const menu = @import("menu.zig");

const Sys = ecs.system.System;
const Scene = ecs.scene.Scene;
const Game = ecs.Game;

// ===================
// VICTORY: a short cinematic (a few stills, each on screen for its own
// time), then the game logo with a prompt to go back to the main menu.
// ===================
pub const victory_system = Sys{ .setup = victorySetup, .update = victoryUpdate, .render = victoryRender, .destroy = victoryDestroy };

const Slide = struct { label: [:0]const u8, color: rl.Color, seconds: f32 };

const SLIDES = [_]Slide{
    .{ .label = "CINEMATIC IMAGE 1", .color = .sky_blue, .seconds = 2.5 },
    .{ .label = "CINEMATIC IMAGE 2", .color = .gold, .seconds = 4.0 },
    .{ .label = "CINEMATIC IMAGE 3", .color = .pink, .seconds = 3.0 },
};
const SLIDES_SECONDS: f32 = blk: {
    var total: f32 = 0;
    for (SLIDES) |slide| total += slide.seconds;
    break :blk total;
};

const FULL_SCREEN = rl.Rectangle{ .x = 0, .y = 0, .width = constants.SCREEN_W, .height = constants.SCREEN_H };

fn victorySetup(_: *Sys, scn: *Scene) void {
    spawnCinematic(scn) catch |err| std.debug.panic("victory setup failed: {}", .{err});
}
fn spawnCinematic(scn: *Scene) !void {
    const id = try scn.entities.new();
    try scn.entities.setComponent(id, comps.Cinematic{});
}
fn victoryDestroy(_: *Sys, scn: *Scene) void {
    var it = scn.entities.query(.{comps.Cinematic});
    if (it.next()) |id| scn.entities.remove(id);
    var req_it = scn.entities.query(.{Game.SwitchRequest});
    if (req_it.next()) |id| scn.entities.remove(id);
}

fn victoryUpdate(_: *Sys, scn: *Scene, dt: f32) void {
    var it = scn.entities.query(.{comps.Cinematic});
    const cinematic = scn.entities.getComponent(it.next() orelse return, comps.Cinematic).?;
    const pressed = rl.getKeyPressed() != .null or ui.clicked();

    if (cinematic.elapsed < SLIDES_SECONDS) {
        // A key during the stills skips straight to the logo.
        cinematic.elapsed = if (pressed) SLIDES_SECONDS else cinematic.elapsed + dt;
        return;
    }
    if (!pressed) return;

    // Only ever one request in flight.
    var pending = scn.entities.query(.{Game.SwitchRequest});
    if (pending.next() != null) return;
    requestMenu(scn) catch |err| std.debug.panic("victory exit failed: {}", .{err});
}
fn requestMenu(scn: *Scene) !void {
    const id = try scn.entities.new();
    try scn.entities.setComponent(id, Game.SwitchRequest{ .to = constants.SCENE_MENU });
}

fn victoryRender(_: *Sys, scn: *Scene) void {
    var it = scn.entities.query(.{comps.Cinematic});
    const elapsed = scn.entities.getComponent(it.next() orelse return, comps.Cinematic).?.elapsed;

    var slide_end: f32 = 0;
    for (SLIDES) |slide| {
        slide_end += slide.seconds;
        if (elapsed >= slide_end) continue;
        ui.placeholder(FULL_SCREEN, slide.label, slide.color);
        return;
    }

    menu.drawBackground();
    sprites.drawCentered(.logo, menu.LOGO);
    if (ui.blink()) {
        ui.textCentered("Press any key to go to the main menu", constants.SCREEN_W / 2.0, menu.PROMPT_Y, 28, .ray_white);
    }
}
