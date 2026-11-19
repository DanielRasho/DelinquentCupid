//! Grid <-> pixel helpers shared by the systems.
const std = @import("std");
const rl = @import("raylib");
const constants = @import("constants.zig");

pub const rect = rl.Rectangle{
    .x = constants.FIELD_LEFT,
    .y = constants.FIELD_TOP,
    .width = constants.FIELD_W,
    .height = constants.FIELD_H,
};

/// The stage: everything between the two side columns.
pub const stage = rl.Rectangle{
    .x = constants.STAGE_X,
    .y = 0,
    .width = constants.STAGE_W,
    .height = constants.SCREEN_H,
};

/// The square tile at (`col`, `row`) of the stage's tile grid. The grid is
/// anchored on the field -- tile (0, 0) is the field's top-left cell -- so
/// it also covers the stage around the field with negative / larger indices.
pub fn tileRect(col: i32, row: i32) rl.Rectangle {
    return .{
        .x = constants.FIELD_LEFT + @as(f32, @floatFromInt(col)) * constants.TILE_SIZE,
        .y = constants.FIELD_TOP + @as(f32, @floatFromInt(row)) * constants.TILE_SIZE,
        .width = constants.TILE_SIZE,
        .height = constants.TILE_SIZE,
    };
}

/// The rectangle a block occupies when it covers `cols` x `rows` cells
/// starting at cell (`col`, `row`).
pub fn blockRect(col: u8, row: u8, cols: u8, rows: u8) rl.Rectangle {
    const inset = constants.BLOCK_INSET;
    return .{
        .x = constants.FIELD_LEFT + @as(f32, @floatFromInt(col)) * constants.CELL_SIZE + inset,
        .y = constants.FIELD_TOP + @as(f32, @floatFromInt(row)) * constants.CELL_SIZE + inset,
        .width = @as(f32, @floatFromInt(cols)) * constants.CELL_SIZE - 2 * inset,
        .height = @as(f32, @floatFromInt(rows)) * constants.CELL_SIZE - 2 * inset,
    };
}

/// Where balls leave from (and where the aim ray starts) for a player at `player_x`.
pub fn launchPoint(player_x: f32) rl.Vector2 {
    return .{ .x = clampToFloor(player_x), .y = constants.FIELD_BOTTOM - constants.BALL_RADIUS - 1 };
}

/// Keeps an x coordinate where a ball resting on the floor fits inside the walls.
pub fn clampToFloor(x: f32) f32 {
    return std.math.clamp(
        x,
        constants.FIELD_LEFT + constants.BALL_RADIUS + 1,
        constants.FIELD_RIGHT - constants.BALL_RADIUS - 1,
    );
}
