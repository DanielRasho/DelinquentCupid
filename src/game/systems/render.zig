const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs");
const constants = @import("../constants.zig");
const comps = @import("../components.zig");
const field = @import("../field.zig");

const Sys = ecs.system.System;
const Scene = ecs.scene.Scene;

pub const render_system = Sys{ .render = gameRender };

const HEALTH_FONT_SIZE: i32 = 24;

// ===================
// RENDER: the greybox world (field, blocks, balls, player).
// ===================

fn gameRender(_: *Sys, scn: *Scene) void {
    // Field, plus the line a block must not cross.
    rl.drawRectangleRec(field.rect, rl.Color.init(40, 44, 52, 255));
    const danger_y = constants.FIELD_TOP + @as(f32, @floatFromInt(constants.DANGER_ROW)) * constants.CELL_SIZE;
    rl.drawLineEx(
        .{ .x = constants.FIELD_LEFT, .y = danger_y },
        .{ .x = constants.FIELD_RIGHT, .y = danger_y },
        2.0,
        rl.fade(.red, 0.5),
    );
    rl.drawRectangleLinesEx(field.rect, 2.0, .light_gray);

    var block_it = scn.entities.query(.{ comps.Block, comps.Position, comps.Size, comps.Health });
    while (block_it.next()) |id| {
        const pos = scn.entities.getComponent(id, comps.Position).?;
        const size = scn.entities.getComponent(id, comps.Size).?;
        const health = scn.entities.getComponent(id, comps.Health).?;
        if (health.current == 0) continue;

        // The more damaged a block is, the darker it gets.
        const left: f32 = @as(f32, @floatFromInt(health.current)) / @as(f32, @floatFromInt(@max(health.max, 1)));
        const shade: u8 = @intFromFloat(90.0 + 110.0 * std.math.clamp(left, 0.0, 1.0));
        const rect = rl.Rectangle{ .x = pos.x, .y = pos.y, .width = size.width, .height = size.height };
        rl.drawRectangleRec(rect, rl.Color.init(shade, shade, shade, 255));
        rl.drawRectangleLinesEx(rect, 2.0, .black);

        var buf: [16]u8 = undefined;
        const text = std.fmt.bufPrintZ(&buf, "{d}", .{health.current}) catch "?";
        const text_w: f32 = @floatFromInt(rl.measureText(text, HEALTH_FONT_SIZE));
        rl.drawText(
            text,
            @intFromFloat(pos.x + (size.width - text_w) / 2.0),
            @intFromFloat(pos.y + (size.height - @as(f32, @floatFromInt(HEALTH_FONT_SIZE))) / 2.0),
            HEALTH_FONT_SIZE,
            .black,
        );
    }

    var ball_it = scn.entities.query(.{ comps.Ball, comps.Position, comps.Circle });
    while (ball_it.next()) |id| {
        const pos = scn.entities.getComponent(id, comps.Position).?;
        const circle = scn.entities.getComponent(id, comps.Circle).?;
        rl.drawCircleV(.{ .x = pos.x, .y = pos.y }, circle.radius, .white);
    }

    var player_it = scn.entities.query(.{ comps.Player, comps.Position });
    while (player_it.next()) |id| {
        const pos = scn.entities.getComponent(id, comps.Position).?;
        const half = constants.PLAYER_SIZE / 2.0;
        rl.drawRectangleRec(
            .{ .x = pos.x - half, .y = pos.y - half, .width = constants.PLAYER_SIZE, .height = constants.PLAYER_SIZE },
            .sky_blue,
        );
    }
}
