const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs");
const constants = @import("../constants.zig");
const comps = @import("../components.zig");
const field = @import("../field.zig");
const ui = @import("../ui.zig");

const Sys = ecs.system.System;
const Scene = ecs.scene.Scene;

// ===================
// TAROT: every `TAROT_EVERY` waves the block system enters the `TAROT`
// phase; this offers `TAROT_OPTIONS` random cards over the stage and
// applies the upgrade of the one the player clicks.
// ===================
pub const tarot_system = Sys{ .update = tarotUpdate, .render = tarotRender };

const Info = struct { name: [:0]const u8, description: [:0]const u8, color: rl.Color };

fn info(card: comps.Card) Info {
    return switch (card) {
        .STRENGTH => .{ .name = "Strength", .description = "+1 sphere damage", .color = .orange },
        .LOVERS => .{ .name = "The Lovers", .description = "+50% love points", .color = .pink },
        .TOWER => .{ .name = "The Tower", .description = "Weaker new blocks", .color = .sky_blue },
    };
}

const CARD_W: f32 = 200;
const CARD_H: f32 = 320;
const CARD_GAP: f32 = 28;
const CARD_PADDING: f32 = 12;
const IMAGE_H: f32 = 170;
const CARDS_W: f32 = constants.TAROT_OPTIONS * CARD_W + (constants.TAROT_OPTIONS - 1) * CARD_GAP;
const CARDS_X: f32 = constants.STAGE_X + (constants.STAGE_W - CARDS_W) / 2.0;
const CARDS_Y: f32 = (constants.SCREEN_H - CARD_H) / 2.0;

fn cardRect(index: usize) rl.Rectangle {
    return .{
        .x = CARDS_X + @as(f32, @floatFromInt(index)) * (CARD_W + CARD_GAP),
        .y = CARDS_Y,
        .width = CARD_W,
        .height = CARD_H,
    };
}

fn tarotUpdate(_: *Sys, scn: *Scene, _: f32) void {
    var game_it = scn.entities.query(.{comps.Turn});
    const game_id = game_it.next().?;
    const turn = scn.entities.getComponent(game_id, comps.Turn).?;
    if (turn.phase != .TAROT) return;

    const draw = scn.entities.getComponent(game_id, comps.TarotDraw).?;
    if (!draw.dealt) {
        deal(draw);
        return;
    }

    if (!ui.clicked()) return;
    for (draw.options, 0..) |card, i| {
        if (!rl.checkCollisionPointRec(rl.getMousePosition(), cardRect(i))) continue;

        const upgrades = scn.entities.getComponent(game_id, comps.Upgrades).?;
        switch (card) {
            .STRENGTH => upgrades.strength += 1,
            .LOVERS => upgrades.lovers += 1,
            .TOWER => upgrades.tower += 1,
        }
        draw.dealt = false;
        turn.phase = .AIMING;
        return;
    }
}

/// Draws the options without repeats while the deck has enough different
/// cards (a partial shuffle of the whole deck); a smaller deck wraps around.
fn deal(draw: *comps.TarotDraw) void {
    var deck = std.enums.values(comps.Card)[0..].*;
    for (&draw.options, 0..) |*option, i| {
        const slot = i % deck.len;
        const pick: usize = @intCast(rl.getRandomValue(@intCast(slot), @intCast(deck.len - 1)));
        std.mem.swap(comps.Card, &deck[slot], &deck[pick]);
        option.* = deck[slot];
    }
    draw.dealt = true;
}

fn tarotRender(_: *Sys, scn: *Scene) void {
    var game_it = scn.entities.query(.{comps.Turn});
    const game_id = game_it.next() orelse return;
    if (scn.entities.getComponent(game_id, comps.Turn).?.phase != .TAROT) return;
    const draw = scn.entities.getComponent(game_id, comps.TarotDraw).?;
    if (!draw.dealt) return;

    rl.drawRectangleRec(field.stage, rl.fade(.black, 0.7));
    const center_x = constants.STAGE_X + constants.STAGE_W / 2.0;
    ui.textCentered("Choose a tarot card", center_x, CARDS_Y - 56, 32, .ray_white);

    for (draw.options, 0..) |card, i| {
        const rect = cardRect(i);
        const card_info = info(card);
        const hovered = rl.checkCollisionPointRec(rl.getMousePosition(), rect);

        rl.drawRectangleRec(rect, if (hovered) .ray_white else .beige);
        rl.drawRectangleLinesEx(rect, if (hovered) 5.0 else 2.0, if (hovered) .gold else .black);

        // Image on top, then the name and what the card does.
        ui.placeholder(.{
            .x = rect.x + CARD_PADDING,
            .y = rect.y + CARD_PADDING,
            .width = CARD_W - 2 * CARD_PADDING,
            .height = IMAGE_H,
        }, "IMAGE", card_info.color);
        const text_x = rect.x + CARD_W / 2.0;
        ui.textCentered(card_info.name, text_x, rect.y + IMAGE_H + 36, 26, .black);
        ui.textCentered(card_info.description, text_x, rect.y + IMAGE_H + 84, 18, .dark_gray);
    }
}
