const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs");
const constants = @import("../constants.zig");
const comps = @import("../components.zig");
const ui = @import("../ui.zig");

const Sys = ecs.system.System;
const Scene = ecs.scene.Scene;

// ===================
// HUD: the wave (turn) counter and the volley's combo above the field, and
// the tarot upgrades collected so far below it.
// ===================
pub const hud_system = Sys{ .render = hudRender };

const WAVE_Y: f32 = (constants.FIELD_TOP - 32) / 2.0;
const UPGRADES_Y: f32 = constants.FIELD_BOTTOM + 48;

fn hudRender(_: *Sys, scn: *Scene) void {
    var game_it = scn.entities.query(.{comps.Turn});
    const game_id = game_it.next() orelse return;
    const turn = scn.entities.getComponent(game_id, comps.Turn).?;
    const upgrades = scn.entities.getComponent(game_id, comps.Upgrades).?;

    var buf: [96]u8 = undefined;
    ui.text(ui.format(&buf, "Wave  {d}", .{turn.wave}), constants.FIELD_LEFT, WAVE_Y, 32, .ray_white);

    const combo = scn.entities.getComponent(game_id, comps.Combo).?.hits;
    if (combo > 0) {
        const label = ui.format(&buf, "{d} combo", .{combo});
        ui.text(label, constants.FIELD_RIGHT - ui.measure(label, 24), WAVE_Y + 6, 24, .gold);
    }

    const cards = ui.format(&buf, "Strength x{d}    Lovers x{d}    Tower x{d}", .{ upgrades.strength, upgrades.lovers, upgrades.tower });
    ui.textCentered(cards, constants.FIELD_LEFT + constants.FIELD_W / 2.0, UPGRADES_Y, 18, .light_gray);
}
