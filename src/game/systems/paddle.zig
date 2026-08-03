const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs");
const constants = @import("constants.zig");
const comps = @import("../components.zig");

const Sys = ecs.system.System;
const Scene = ecs.scene.Scene;

const PADDLE_SPEED: f32 = 300;
const PADDLE_WIDTH: f32 = 120.0;
const PADDLE_HEIGHT: f32 = 20.0;

// ===================
// PADDLE
// ===================

pub const paddle_system = Sys{ .setup = paddleSetup, .update = paddleUpdate, .destroy = paddleDestroy };

fn paddleSetup(_: *Sys, scn: *Scene) void {
    spawnPaddle(scn) catch |err| std.debug.panic("paddle setup failed: {}", .{err});
}
fn spawnPaddle(scn: *Scene) !void {
    const id = try scn.entities.new();
    try scn.entities.setComponent(id, comps.Position{
        .x = constants.SCREEN_W / 2.0 - PADDLE_WIDTH / 2.0,
        .y = constants.SCREEN_H - 40.0,
    });
    try scn.entities.setComponent(id, comps.Rectangle{ .width = PADDLE_WIDTH, .height = PADDLE_HEIGHT });
    try scn.entities.setComponent(id, comps.Paddle{});
}
fn paddleDestroy(_: *Sys, scn: *Scene) void {
    var it = scn.entities.query(.{comps.Paddle});
    if (it.next()) |id| scn.entities.remove(id);
}

fn paddleUpdate(_: *Sys, scn: *Scene, dt: f32) void {
    var status_it = scn.entities.query(.{comps.GameStatus});
    const status = scn.entities.getComponent(status_it.next().?, comps.GameStatus).?;
    if (status.status == .WIN or status.status == .LOOSE) return;

    var it = scn.entities.query(.{ comps.Paddle, comps.Position, comps.Rectangle });
    while (it.next()) |id| {
        const pos = scn.entities.getComponent(id, comps.Position).?;
        const size = scn.entities.getComponent(id, comps.Rectangle).?;

        if (rl.isKeyDown(.left) or rl.isKeyDown(.a)) pos.x -= PADDLE_SPEED * dt;
        if (rl.isKeyDown(.right) or rl.isKeyDown(.d)) pos.x += PADDLE_SPEED * dt;

        if (pos.x < 0) pos.x = 0;
        if (pos.x + size.width > constants.SCREEN_W) pos.x = constants.SCREEN_W - size.width;
    }
}
