const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs");
const constants = @import("../constants.zig");
const comps = @import("../components.zig");
const ui = @import("../ui.zig");

const Sys = ecs.system.System;
const Scene = ecs.scene.Scene;

// ===================
// SHOP: the left column under the girl. Love points, the button that turns
// them into spheres (only between turns), and the spheres owned.
// ===================
pub const shop_system = Sys{ .update = shopUpdate, .render = shopRender };

const CENTER_X: f32 = constants.LEFT_COLUMN_X + constants.COLUMN_CONTENT_W / 2.0;
const POINTS_Y: f32 = constants.COLUMN_BODY_Y;
const LABEL_Y: f32 = POINTS_Y + 40;
const BUY_RECT = rl.Rectangle{ .x = CENTER_X - 100, .y = LABEL_Y + 34, .width = 200, .height = 44 };
const SLOTS_Y: f32 = BUY_RECT.y + BUY_RECT.height + 24;
const SLOT_SIZE: f32 = 56;

fn shopUpdate(_: *Sys, scn: *Scene, _: f32) void {
    var game_it = scn.entities.query(.{comps.Turn});
    const game_id = game_it.next().?;
    if (scn.entities.getComponent(game_id, comps.Turn).?.phase != .AIMING) return;
    if (!ui.clickedIn(BUY_RECT)) return;

    const love = scn.entities.getComponent(game_id, comps.LovePoints).?;
    if (love.points < constants.SPHERE_COST) return;
    love.points -= constants.SPHERE_COST;
    // Only one kind of sphere exists so far; "random" will pick among kinds.
    scn.entities.getComponent(game_id, comps.BallStock).?.count += 1;
}

fn shopRender(_: *Sys, scn: *Scene) void {
    var game_it = scn.entities.query(.{comps.Turn});
    const game_id = game_it.next() orelse return;
    const open = scn.entities.getComponent(game_id, comps.Turn).?.phase == .AIMING;
    const points = scn.entities.getComponent(game_id, comps.LovePoints).?.points;
    const balls = scn.entities.getComponent(game_id, comps.BallStock).?.count;

    var buf: [64]u8 = undefined;
    ui.textCentered(ui.format(&buf, "{d}", .{points}), CENTER_X, POINTS_Y, 36, .ray_white);
    ui.textCentered("Love Points", CENTER_X, LABEL_Y, 20, .ray_white);
    ui.button(
        BUY_RECT,
        ui.format(&buf, "Get sphere ({d})", .{constants.SPHERE_COST}),
        20,
        open and points >= constants.SPHERE_COST,
    );

    // One slot per kind of sphere owned, with how many underneath.
    const slot = rl.Rectangle{ .x = constants.LEFT_COLUMN_X + 16, .y = SLOTS_Y, .width = SLOT_SIZE, .height = SLOT_SIZE };
    rl.drawRectangleLinesEx(slot, 2.0, .light_gray);
    rl.drawCircleV(.{ .x = slot.x + SLOT_SIZE / 2.0, .y = slot.y + SLOT_SIZE / 2.0 }, 16, .white);
    ui.textCentered(ui.format(&buf, "{d}", .{balls}), slot.x + SLOT_SIZE / 2.0, slot.y + SLOT_SIZE + 6, 20, .ray_white);
}
