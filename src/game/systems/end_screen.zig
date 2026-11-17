const std = @import("std");
const rl = @import("raylib");
const zgui = @import("zgui");
const ecs = @import("ecs");
const constants = @import("../constants.zig");

const Sys = ecs.system.System;
const Scene = ecs.scene.Scene;
const Game = ecs.Game;

const TITLE_FONT_SIZE: i32 = 96;
const HINT_FONT_SIZE: i32 = 24;
const HINT_GAP: f32 = 24.0;
const HINT_TEXT: [:0]const u8 = "Click or press SPACE to play again";

// ===================
// END SCREENS
// ===================

pub const lose_system = EndScreen("GAME OVER", .red);

/// Builds a system that draws `title` in the middle of an otherwise empty
/// screen and goes back to the gameplay scene on a click or SPACE. Each call yields a
/// distinct system (its own callbacks), so one file serves every end screen.
fn EndScreen(comptime title: [:0]const u8, comptime title_color: rl.Color) Sys {
    const Impl = struct {
        fn update(_: *Sys, scn: *Scene, _: f32) void {
            // A click on a debug panel is not a click on the screen.
            const clicked = rl.isMouseButtonPressed(.left) and !zgui.io.getWantCaptureMouse();
            if (!rl.isKeyPressed(.space) and !clicked) return;
            requestRestart(scn) catch |err| std.debug.panic("end screen restart failed: {}", .{err});
        }
        fn requestRestart(scn: *Scene) !void {
            const id = try scn.entities.new();
            try scn.entities.setComponent(id, Game.SwitchRequest{ .to = constants.SCENE_GAME });
        }
        fn render(_: *Sys, _: *Scene) void {
            const title_y = constants.SCREEN_H / 2.0 - @as(f32, @floatFromInt(TITLE_FONT_SIZE)) / 2.0;
            const hint_y = title_y + @as(f32, @floatFromInt(TITLE_FONT_SIZE)) + HINT_GAP;
            drawCentered(title, TITLE_FONT_SIZE, title_y, title_color);
            drawCentered(HINT_TEXT, HINT_FONT_SIZE, hint_y, .light_gray);
        }
        fn destroy(_: *Sys, scn: *Scene) void {
            var it = scn.entities.query(.{Game.SwitchRequest});
            if (it.next()) |id| scn.entities.remove(id);
        }
    };
    return .{ .update = Impl.update, .render = Impl.render, .destroy = Impl.destroy };
}

fn drawCentered(text: [:0]const u8, font_size: i32, y: f32, color: rl.Color) void {
    const screen_w: i32 = @intFromFloat(constants.SCREEN_W);
    const x = @divTrunc(screen_w - rl.measureText(text, font_size), 2);
    rl.drawText(text, x, @intFromFloat(y), font_size, color);
}
