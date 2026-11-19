const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs");
const constants = @import("../constants.zig");
const comps = @import("../components.zig");
const ui = @import("../ui.zig");
const spheres = @import("../spheres.zig");

const Sys = ecs.system.System;
const Scene = ecs.scene.Scene;

// ===================
// SHOP: the left column under the girl. Love points, the button that turns
// them into a sphere of a random kind (only between turns), and the spheres
// owned of each kind.
// ===================
pub const shop_system = Sys{ .update = shopUpdate, .render = shopRender };

const CENTER_X: f32 = constants.LEFT_COLUMN_X + constants.COLUMN_CONTENT_W / 2.0;
const POINTS_Y: f32 = constants.COLUMN_BODY_Y;
const LABEL_Y: f32 = POINTS_Y + 40;
const BUY_RECT = rl.Rectangle{ .x = CENTER_X - 100, .y = LABEL_Y + 34, .width = 200, .height = 44 };
const SLOTS_Y: f32 = BUY_RECT.y + BUY_RECT.height + 24;
const SLOT_SIZE: f32 = 56;
/// Slots wrap into rows of this many, each in an equal share of the column.
const SLOTS_PER_ROW: usize = 3;
const SLOT_CELL_W: f32 = constants.COLUMN_CONTENT_W / @as(f32, SLOTS_PER_ROW);
/// A slot, its name and its count underneath.
const SLOT_CELL_H: f32 = SLOT_SIZE + 52;

fn shopUpdate(_: *Sys, scn: *Scene, _: f32) void {
    var game_it = scn.entities.query(.{comps.Turn});
    const game_id = game_it.next().?;
    if (scn.entities.getComponent(game_id, comps.Turn).?.phase != .AIMING) return;
    if (!ui.clickedIn(BUY_RECT)) return;

    const love = scn.entities.getComponent(game_id, comps.LovePoints).?;
    if (love.points < constants.SPHERE_COST) return;
    love.points -= constants.SPHERE_COST;
    scn.entities.getComponent(game_id, comps.BallStock).?.of(spheres.roll()).* += 1;
}

fn shopRender(_: *Sys, scn: *Scene) void {
    var game_it = scn.entities.query(.{comps.Turn});
    const game_id = game_it.next() orelse return;
    const open = scn.entities.getComponent(game_id, comps.Turn).?.phase == .AIMING;
    const points = scn.entities.getComponent(game_id, comps.LovePoints).?.points;
    const stock = scn.entities.getComponent(game_id, comps.BallStock).?;

    var buf: [64]u8 = undefined;
    ui.textCentered(ui.format(&buf, "{d}", .{points}), CENTER_X, POINTS_Y, 36, .ray_white);
    ui.textCentered("Love Points", CENTER_X, LABEL_Y, 20, .ray_white);
    ui.button(
        BUY_RECT,
        ui.format(&buf, "Get sphere ({d})", .{constants.SPHERE_COST}),
        20,
        open and points >= constants.SPHERE_COST,
    );

    // One slot per kind of sphere owned, with its name and how many underneath.
    var shown: usize = 0;
    for (std.enums.values(comps.SphereKind)) |kind| {
        const count = stock.of(kind).*;
        if (count == 0) continue;
        const kind_info = spheres.info(kind);

        const center_x = constants.LEFT_COLUMN_X + (@as(f32, @floatFromInt(shown % SLOTS_PER_ROW)) + 0.5) * SLOT_CELL_W;
        const top = SLOTS_Y + @as(f32, @floatFromInt(shown / SLOTS_PER_ROW)) * SLOT_CELL_H;
        const slot = rl.Rectangle{ .x = center_x - SLOT_SIZE / 2.0, .y = top, .width = SLOT_SIZE, .height = SLOT_SIZE };
        rl.drawRectangleLinesEx(slot, 2.0, .light_gray);
        rl.drawCircleV(.{ .x = center_x, .y = top + SLOT_SIZE / 2.0 }, 16, kind_info.color);
        ui.textCentered(kind_info.name, center_x, top + SLOT_SIZE + 6, 14, .light_gray);
        ui.textCentered(ui.format(&buf, "{d}", .{count}), center_x, top + SLOT_SIZE + 24, 20, .ray_white);
        shown += 1;
    }
}
