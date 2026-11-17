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

/// The rectangle a block occupies inside cell (`col`, `row`).
pub fn blockRect(col: u8, row: u8) rl.Rectangle {
    const inset = constants.BLOCK_INSET;
    return .{
        .x = constants.FIELD_LEFT + @as(f32, @floatFromInt(col)) * constants.CELL_SIZE + inset,
        .y = constants.FIELD_TOP + @as(f32, @floatFromInt(row)) * constants.CELL_SIZE + inset,
        .width = constants.CELL_SIZE - 2 * inset,
        .height = constants.CELL_SIZE - 2 * inset,
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
