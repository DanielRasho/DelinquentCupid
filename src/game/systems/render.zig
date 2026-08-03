const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs");
const comps = @import("../components.zig");

const Sys = ecs.system.System;
const Scene = ecs.scene.Scene;

pub const render_system = Sys{ .render = gameRender };

// ===================
// RENDER
// ===================

fn gameRender(_: *Sys, scn: *Scene) void {
    var brick_it = scn.entities.query(.{ comps.Brick, comps.Position, comps.Rectangle, comps.Color });
    while (brick_it.next()) |id| {
        const pos = scn.entities.getComponent(id, comps.Position).?;
        const size = scn.entities.getComponent(id, comps.Rectangle).?;
        const color = scn.entities.getComponent(id, comps.Color).?;
        const rect = rl.Rectangle{ .x = pos.x, .y = pos.y, .width = size.width, .height = size.height };
        rl.drawRectangleRec(rect, color.color);
        rl.drawRectangleLinesEx(rect, 1.0, .black);
    }

    var ball_it = scn.entities.query(.{ comps.Ball, comps.Position, comps.Circle });
    while (ball_it.next()) |id| {
        const pos = scn.entities.getComponent(id, comps.Position).?;
        const circle = scn.entities.getComponent(id, comps.Circle).?;
        rl.drawCircleV(.{ .x = pos.x, .y = pos.y }, circle.radius, .white);
    }

    var paddle_it = scn.entities.query(.{ comps.Paddle, comps.Position, comps.Rectangle });
    while (paddle_it.next()) |id| {
        const pos = scn.entities.getComponent(id, comps.Position).?;
        const size = scn.entities.getComponent(id, comps.Rectangle).?;
        rl.drawRectangleRec(.{ .x = pos.x, .y = pos.y, .width = size.width, .height = size.height }, .white);
    }
}
