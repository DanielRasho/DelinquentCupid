const rl = @import("raylib");
const ecs = @import("ecs");
const constants = @import("../constants.zig");
const sakura = @import("../sakura.zig");

const Sys = ecs.system.System;
const Scene = ecs.scene.Scene;

// ===================
// BACKDROP: the side columns' sakura gradient, with a rose seam where each
// meets the stage. Registered right after `Render`, so the portraits, shop
// and cupid widgets all draw over it.
// ===================
pub const backdrop_system = Sys{ .render = backdropRender };

const COLUMNS = [_]rl.Rectangle{
    .{ .x = 0, .y = 0, .width = constants.COLUMN_W, .height = constants.SCREEN_H },
    .{ .x = constants.SCREEN_W - constants.COLUMN_W, .y = 0, .width = constants.COLUMN_W, .height = constants.SCREEN_H },
};
const SEAM_W: f32 = 3;

fn backdropRender(_: *Sys, _: *Scene) void {
    for (COLUMNS, 0..) |column, side| {
        rl.drawRectangleGradientV(
            @intFromFloat(column.x),
            @intFromFloat(column.y),
            @intFromFloat(column.width),
            @intFromFloat(column.height),
            sakura.night,
            sakura.dusk,
        );
        // The left column's seam is on its right edge, the right column's on its left.
        const seam_x = if (side == 0) column.x + column.width - SEAM_W else column.x;
        rl.drawRectangleRec(.{ .x = seam_x, .y = 0, .width = SEAM_W, .height = column.height }, rl.fade(sakura.blossom_deep, 0.55));
    }
}
