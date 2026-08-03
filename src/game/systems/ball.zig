const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs");
const constants = @import("constants.zig");
const comps = @import("../components.zig");

const Sys = ecs.system.System;
const Scene = ecs.scene.Scene;

const BALL_RADIUS: f32 = 8.0;
const BALL_SPEED: f32 = 350.0;

// ===================
// BALL
// ===================

pub const ball_system = Sys{ .setup = ballSetup, .update = ballUpdate, .destroy = ballDestroy };

fn ballSetup(_: *Sys, scn: *Scene) void {
    spawnBall(scn) catch |err| std.debug.panic("ball setup failed: {}", .{err});
}
fn spawnBall(scn: *Scene) !void {
    // Paddle must already exist (registered/set up before the ball system).
    var paddle_it = scn.entities.query(.{ comps.Paddle, comps.Position, comps.Rectangle });
    const paddle_id = paddle_it.next().?;
    const paddle_pos = scn.entities.getComponent(paddle_id, comps.Position).?;
    const paddle_size = scn.entities.getComponent(paddle_id, comps.Rectangle).?;

    const id = try scn.entities.new();
    try scn.entities.setComponent(id, comps.Position{
        .x = paddle_pos.x + paddle_size.width / 2.0,
        .y = paddle_pos.y - BALL_RADIUS - 1.0,
    });
    try scn.entities.setComponent(id, comps.Velocity{ .x = 0, .y = 0 });
    try scn.entities.setComponent(id, comps.Circle{ .radius = BALL_RADIUS });
    try scn.entities.setComponent(id, comps.Ball{ .speed = BALL_SPEED });
}
fn ballDestroy(_: *Sys, scn: *Scene) void {
    var it = scn.entities.query(.{comps.Ball});
    if (it.next()) |id| scn.entities.remove(id);
}

fn ballUpdate(_: *Sys, scn: *Scene, dt: f32) void {
    var game_it = scn.entities.query(.{comps.GameStatus});
    const game_id = game_it.next().?;
    const status = scn.entities.getComponent(game_id, comps.GameStatus).?;
    if (status.status != .READY and status.status != .PLAYING) return;

    var paddle_it = scn.entities.query(.{ comps.Paddle, comps.Position, comps.Rectangle });
    const paddle_id = paddle_it.next().?;
    const paddle_pos = scn.entities.getComponent(paddle_id, comps.Position).?;
    const paddle_size = scn.entities.getComponent(paddle_id, comps.Rectangle).?;
    const paddle_center = paddle_pos.x + paddle_size.width / 2.0;

    var ball_it = scn.entities.query(.{ comps.Ball, comps.Position, comps.Velocity, comps.Circle });
    const ball_id = ball_it.next().?;
    const ball = scn.entities.getComponent(ball_id, comps.Ball).?;
    const pos = scn.entities.getComponent(ball_id, comps.Position).?;
    const vel = scn.entities.getComponent(ball_id, comps.Velocity).?;
    const circle = scn.entities.getComponent(ball_id, comps.Circle).?;

    if (status.status == .READY) {
        pos.* = .{ .x = paddle_center, .y = paddle_pos.y - circle.radius - 1.0 };
        vel.* = .{ .x = 0, .y = 0 };

        if (rl.isKeyPressed(.space)) {
            const dir = comps.Velocity{ .x = 0.35, .y = -0.9 };
            const len = @sqrt(dir.x * dir.x + dir.y * dir.y);
            vel.* = .{ .x = dir.x / len * ball.speed, .y = dir.y / len * ball.speed };
            status.status = .PLAYING;
        }
        return;
    }

    // status == .PLAYING

    // Keep the ball's speed pinned to the (HUD-editable) target speed.
    const cur_len = @sqrt(vel.x * vel.x + vel.y * vel.y);
    if (cur_len > 0.0001) {
        const scale = ball.speed / cur_len;
        vel.x *= scale;
        vel.y *= scale;
    }
    pos.x += vel.x * dt;
    pos.y += vel.y * dt;

    // Bottom wall: lose a life
    if (pos.y - circle.radius > constants.SCREEN_H) {
        const lives = scn.entities.getComponent(game_id, comps.Lives).?;
        lives.count -= 1;
        if (lives.count == 0) {
            status.status = .LOOSE;
        } else {
            pos.* = .{ .x = paddle_center, .y = paddle_pos.y - circle.radius - 1.0 };
            vel.* = .{ .x = 0, .y = 0 };
            status.status = .READY;
        }
        return;
    }

    // Left/right walls
    if (pos.x - circle.radius <= 0) {
        pos.x = circle.radius;
        vel.x = -vel.x;
    } else if (pos.x + circle.radius >= constants.SCREEN_W) {
        pos.x = constants.SCREEN_W - circle.radius;
        vel.x = -vel.x;
    }
    // Top wall
    if (pos.y - circle.radius <= 0) {
        pos.y = circle.radius;
        vel.y = -vel.y;
    }

    // Paddle bounce
    const paddle_rect = rl.Rectangle{ .x = paddle_pos.x, .y = paddle_pos.y, .width = paddle_size.width, .height = paddle_size.height };
    if (vel.y > 0 and rl.checkCollisionCircleRec(.{ .x = pos.x, .y = pos.y }, circle.radius, paddle_rect)) {
        pos.y = paddle_pos.y - circle.radius;

        const hit_pos = (pos.x - paddle_center) / (paddle_size.width / 2.0);
        const speed = @sqrt(vel.x * vel.x + vel.y * vel.y);

        vel.x = hit_pos * speed;
        vel.y = -@abs(vel.y);
    }
}
