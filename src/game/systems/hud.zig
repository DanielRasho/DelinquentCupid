const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs");
const constants = @import("../constants.zig");
const comps = @import("../components.zig");
const sakura = @import("../sakura.zig");
const ui = @import("../ui.zig");

const Sys = ecs.system.System;
const Scene = ecs.scene.Scene;

// ===================
// HUD: the wave (turn) counter and the volley's combo above the field, and
// the tarot upgrades collected so far under the player. Sakura pills, so
// they read over the map.
// ===================
pub const hud_system = Sys{ .render = hudRender };

const PILL_H: f32 = 44;
const PILL_Y: f32 = (constants.FIELD_TOP - PILL_H) / 2.0;
const PILL_PAD: f32 = 14;
const WAVE_SIZE: i32 = 28;
const COMBO_SIZE: i32 = 22;

const UPGRADES_H: f32 = 30;
const UPGRADES_SIZE: i32 = 18;
/// Under the player, who stands just below the field.
const UPGRADES_Y: f32 = constants.FIELD_BOTTOM + constants.PLAYER_SIZE + 16;

fn hudRender(_: *Sys, scn: *Scene) void {
    var game_it = scn.entities.query(.{comps.Turn});
    const game_id = game_it.next() orelse return;
    const turn = scn.entities.getComponent(game_id, comps.Turn).?;
    const upgrades = scn.entities.getComponent(game_id, comps.Upgrades).?;

    var buf: [96]u8 = undefined;
    const wave = ui.format(&buf, "Wave  {d}", .{turn.wave});
    const wave_pill = rl.Rectangle{
        .x = constants.FIELD_LEFT,
        .y = PILL_Y,
        .width = ui.measure(wave, WAVE_SIZE) + 2 * PILL_PAD,
        .height = PILL_H,
    };
    ui.panel(wave_pill, rl.fade(sakura.night, 0.85), sakura.blossom);
    ui.textInRect(wave, wave_pill, WAVE_SIZE, sakura.petal_white);

    const combo = scn.entities.getComponent(game_id, comps.Combo).?.hits;
    if (combo > 0) {
        const label = ui.format(&buf, "{d} combo", .{combo});
        const width = ui.measure(label, COMBO_SIZE) + 2 * PILL_PAD;
        const combo_pill = rl.Rectangle{ .x = constants.FIELD_RIGHT - width, .y = PILL_Y, .width = width, .height = PILL_H };
        ui.panel(combo_pill, sakura.blossom_deep, sakura.blossom_light);
        ui.textInRect(label, combo_pill, COMBO_SIZE, sakura.petal_white);
    }

    const cards = ui.format(&buf, "Strength x{d}    Lovers x{d}    Tower x{d}", .{ upgrades.strength, upgrades.lovers, upgrades.tower });
    const cards_w = ui.measure(cards, UPGRADES_SIZE) + 2 * PILL_PAD;
    const cards_pill = rl.Rectangle{
        .x = constants.FIELD_LEFT + (constants.FIELD_W - cards_w) / 2.0,
        .y = UPGRADES_Y,
        .width = cards_w,
        .height = UPGRADES_H,
    };
    ui.panel(cards_pill, rl.fade(sakura.night, 0.85), rl.fade(sakura.blossom, 0.6));
    ui.textInRect(cards, cards_pill, UPGRADES_SIZE, sakura.blossom_light);
}
