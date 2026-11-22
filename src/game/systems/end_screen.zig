const std = @import("std");
const rl = @import("raylib");
const zgui = @import("zgui");
const ecs = @import("ecs");
const constants = @import("../constants.zig");
const ui = @import("../ui.zig");
const sprites = @import("../sprites.zig");
const menu = @import("menu.zig");

const Sys = ecs.system.System;
const Scene = ecs.scene.Scene;
const Game = ecs.Game;

/// The title goes under the logo, which sits where the main menu has it.
const TITLE_Y: f32 = menu.LOGO.y + menu.LOGO.height + 40;
const TITLE_FONT_SIZE: i32 = 96;
const HINT_FONT_SIZE: i32 = 24;
const HINT_GAP: f32 = 24.0;
const HINT_TEXT: [:0]const u8 = "Click or press SPACE to play again";

// ===================
// END SCREENS
// ===================

// Winning has its own scene, see victory.zig.
pub const lose_system = EndScreen("GAME OVER", .red);

/// Builds a system that draws the logo with `title` under it on an otherwise
/// empty screen and goes back to the gameplay scene on a click or SPACE. Each call yields a
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
            menu.drawBackground();
            sprites.drawCentered(.logo, menu.LOGO);
            const hint_y = TITLE_Y + @as(f32, @floatFromInt(TITLE_FONT_SIZE)) + HINT_GAP;
            drawCentered(title, TITLE_FONT_SIZE, TITLE_Y, title_color);
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
    ui.textCentered(text, constants.SCREEN_W / 2.0, y, font_size, color);
}
