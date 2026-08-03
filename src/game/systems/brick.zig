const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs");
const constants = @import("constants.zig");
const comps = @import("../components.zig");

const Sys = ecs.system.System;
const Scene = ecs.scene.Scene;
const BRICK_ROWS: u8 = 5;
const BRICK_COLUMNS: u8 = 5;
const BRICK_GAP: f32 = 6.0;
const BRICK_TOP_OFFSET: f32 = 60.0;
const BRICK_WIDTH: f32 = 90.0;
const BRICK_HEIGHT: f32 = 28.0;
const BRICK_ROW_COLORS = [_]rl.Color{ .red, .orange, .yellow, .green, .sky_blue };

pub const brick_system = Sys{ .setup = brickSetup, .update = brickUpdate, .destroy = brickDestroy };

// ===================
// BRICKS
// ===================

fn brickSetup(_: *Sys, scn: *Scene) void {
    spawnBricks(scn) catch |err| std.debug.panic("brick setup failed: {}", .{err});
}
fn spawnBricks(scn: *Scene) !void {
    const columns_f: f32 = @floatFromInt(BRICK_COLUMNS);
    const total_width: f32 = columns_f * BRICK_WIDTH + (columns_f - 1) * BRICK_GAP;
    const left_offset: f32 = (constants.SCREEN_W - total_width) / 2.0;

    for (0..BRICK_ROWS) |row| {
        for (0..BRICK_COLUMNS) |col| {
            const x: f32 = left_offset + @as(f32, @floatFromInt(col)) * (BRICK_WIDTH + BRICK_GAP);
            const y: f32 = BRICK_TOP_OFFSET + @as(f32, @floatFromInt(row)) * (BRICK_HEIGHT + BRICK_GAP);

            const id = try scn.entities.new();
            try scn.entities.setComponent(id, comps.Position{ .x = x, .y = y });
            try scn.entities.setComponent(id, comps.Rectangle{ .width = BRICK_WIDTH, .height = BRICK_HEIGHT });
            try scn.entities.setComponent(id, comps.Color{ .color = BRICK_ROW_COLORS[row % BRICK_ROW_COLORS.len] });
            try scn.entities.setComponent(id, comps.Brick{});
        }
    }

    // Game singleton must already exist (registered/set up before bricks).
    var game_it = scn.entities.query(.{comps.Score});
    const score = scn.entities.getComponent(game_it.next().?, comps.Score).?;
    score.total = @as(u32, BRICK_ROWS) * @as(u32, BRICK_COLUMNS);
    score.broken = 0;
}
fn brickDestroy(_: *Sys, scn: *Scene) void {
    var leftover: std.ArrayList(ecs.entity.EntityID) = .empty;
    defer leftover.deinit(scn.allocator);

    var it = scn.entities.query(.{comps.Brick});
    while (it.next()) |id| {
        leftover.append(scn.allocator, id) catch |err| std.debug.panic("brick destroy failed: {}", .{err});
    }
    for (leftover.items) |id| {
        scn.entities.remove(id);
    }
}

fn brickUpdate(_: *Sys, scn: *Scene, dt: f32) void {
    _ = dt;
    var game_it = scn.entities.query(.{comps.GameStatus});
    const game_id = game_it.next().?;
    const status = scn.entities.getComponent(game_id, comps.GameStatus).?;
    if (status.status != .PLAYING) return;

    var ball_it = scn.entities.query(.{ comps.Ball, comps.Position, comps.Velocity, comps.Circle });
    const ball_id = ball_it.next().?;
    const pos = scn.entities.getComponent(ball_id, comps.Position).?;
    const vel = scn.entities.getComponent(ball_id, comps.Velocity).?;
    const circle = scn.entities.getComponent(ball_id, comps.Circle).?;

    var it = scn.entities.query(.{ comps.Brick, comps.Position, comps.Rectangle });
    while (it.next()) |brick_id| {
        const brick_pos = scn.entities.getComponent(brick_id, comps.Position).?;
        const brick_size = scn.entities.getComponent(brick_id, comps.Rectangle).?;
        const brick_rect = rl.Rectangle{ .x = brick_pos.x, .y = brick_pos.y, .width = brick_size.width, .height = brick_size.height };

        if (!rl.checkCollisionCircleRec(.{ .x = pos.x, .y = pos.y }, circle.radius, brick_rect)) continue;

        const closest_x = std.math.clamp(pos.x, brick_rect.x, brick_rect.x + brick_rect.width);
        const closest_y = std.math.clamp(pos.y, brick_rect.y, brick_rect.y + brick_rect.height);
        const dx = @abs(pos.x - closest_x);
        const dy = @abs(pos.y - closest_y);

        if (dx > dy) {
            vel.x = -vel.x;
        } else {
            vel.y = -vel.y;
        }

        // It's safe to remove while iterating because, we will stop iteration after this.
        scn.entities.remove(brick_id);

        const score = scn.entities.getComponent(game_id, comps.Score).?;
        score.broken += 1;
        if (score.broken == score.total) {
            status.status = .WIN;
        }

        break;
    }
}
