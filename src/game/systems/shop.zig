const std = @import("std");
const rl = @import("raylib");
const zgui = @import("zgui");
const ecs = @import("ecs");
const constants = @import("../constants.zig");
const comps = @import("../components.zig");

const Sys = ecs.system.System;
const Scene = ecs.scene.Scene;

// ===================
// SHOP: spend the coins dropped by blocks on extra balls, between turns.
// ===================
pub const shop_system = Sys{ .update = shopUpdate, .render = shopRender };

const Offer = struct { amount: u32, cost: u32, rect: rl.Rectangle };

const STATS_Y: i32 = @intFromFloat(constants.FIELD_BOTTOM + 42);
const STATS_FONT_SIZE: i32 = 20;
const BUTTON_Y: f32 = constants.FIELD_BOTTOM + 70;
const BUTTON_H: f32 = 44;
const BUTTON_GAP: f32 = 16;
const BUTTON_W: f32 = (constants.FIELD_W - BUTTON_GAP) / 2.0;
const BUTTON_FONT_SIZE: i32 = 20;

const OFFERS = [_]Offer{
    .{
        .amount = constants.SHOP_SMALL_AMOUNT,
        .cost = constants.SHOP_SMALL_COST,
        .rect = .{ .x = constants.FIELD_LEFT, .y = BUTTON_Y, .width = BUTTON_W, .height = BUTTON_H },
    },
    .{
        .amount = constants.SHOP_BIG_AMOUNT,
        .cost = constants.SHOP_BIG_COST,
        .rect = .{ .x = constants.FIELD_LEFT + BUTTON_W + BUTTON_GAP, .y = BUTTON_Y, .width = BUTTON_W, .height = BUTTON_H },
    },
};

fn shopUpdate(_: *Sys, scn: *Scene, _: f32) void {
    var game_it = scn.entities.query(.{comps.Turn});
    const game_id = game_it.next().?;
    if (scn.entities.getComponent(game_id, comps.Turn).?.phase != .AIMING) return;

    if (!rl.isMouseButtonPressed(.left) or zgui.io.getWantCaptureMouse()) return;
    const mouse = rl.getMousePosition();

    const wallet = scn.entities.getComponent(game_id, comps.Wallet).?;
    const stock = scn.entities.getComponent(game_id, comps.BallStock).?;
    for (OFFERS) |offer| {
        if (!rl.checkCollisionPointRec(mouse, offer.rect)) continue;
        if (wallet.coins < offer.cost) return;
        wallet.coins -= offer.cost;
        stock.count += offer.amount;
        return;
    }
}

fn shopRender(_: *Sys, scn: *Scene) void {
    var game_it = scn.entities.query(.{comps.Turn});
    const game_id = game_it.next() orelse return;
    const open = scn.entities.getComponent(game_id, comps.Turn).?.phase == .AIMING;
    const coins = scn.entities.getComponent(game_id, comps.Wallet).?.coins;
    const balls = scn.entities.getComponent(game_id, comps.BallStock).?.count;

    var buf: [64]u8 = undefined;
    const stats = std.fmt.bufPrintZ(&buf, "Balls: {d}    Coins: {d}", .{ balls, coins }) catch "?";
    rl.drawText(stats, @intFromFloat(constants.FIELD_LEFT), STATS_Y, STATS_FONT_SIZE, .ray_white);

    const mouse = rl.getMousePosition();
    for (OFFERS) |offer| {
        const available = open and coins >= offer.cost;
        const hovered = available and rl.checkCollisionPointRec(mouse, offer.rect);
        const fill: rl.Color = if (hovered) .light_gray else if (available) .gray else rl.fade(.gray, 0.3);
        const ink: rl.Color = if (available) .black else .gray;

        rl.drawRectangleRec(offer.rect, fill);
        rl.drawRectangleLinesEx(offer.rect, 2.0, ink);

        const label = std.fmt.bufPrintZ(&buf, "Buy {d}  ({d})", .{ offer.amount, offer.cost }) catch "?";
        const text_w: f32 = @floatFromInt(rl.measureText(label, BUTTON_FONT_SIZE));
        rl.drawText(
            label,
            @intFromFloat(offer.rect.x + (offer.rect.width - text_w) / 2.0),
            @intFromFloat(offer.rect.y + (offer.rect.height - @as(f32, @floatFromInt(BUTTON_FONT_SIZE))) / 2.0),
            BUTTON_FONT_SIZE,
            ink,
        );
    }
}
