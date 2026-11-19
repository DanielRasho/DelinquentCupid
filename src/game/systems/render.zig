const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs");
const constants = @import("../constants.zig");
const comps = @import("../components.zig");
const field = @import("../field.zig");
const spheres = @import("../spheres.zig");

const Sys = ecs.system.System;
const Scene = ecs.scene.Scene;

pub const render_system = Sys{ .render = gameRender };

const HEALTH_FONT_SIZE: i32 = 24;

// ===================
// RENDER: the greybox world (field, blocks, balls, player).
// ===================

/// Stand-in for the tilemap: a checkerboard of the stage's square tiles,
/// clipped to the stage (tiles cut by its edges show partially).
fn drawStage() void {
    const stage = field.stage;
    const tile = constants.TILE_SIZE;
    const first_col: i32 = @intFromFloat(@floor((stage.x - constants.FIELD_LEFT) / tile));
    const last_col: i32 = @intFromFloat(@ceil((stage.x + stage.width - constants.FIELD_LEFT) / tile));
    const first_row: i32 = @intFromFloat(@floor((stage.y - constants.FIELD_TOP) / tile));
    const last_row: i32 = @intFromFloat(@ceil((stage.y + stage.height - constants.FIELD_TOP) / tile));

    rl.beginScissorMode(@intFromFloat(stage.x), @intFromFloat(stage.y), @intFromFloat(stage.width), @intFromFloat(stage.height));
    defer rl.endScissorMode();

    var row = first_row;
    while (row < last_row) : (row += 1) {
        var col = first_col;
        while (col < last_col) : (col += 1) {
            const is_dark = @mod(col + row, 2) == 0;
            const shade: u8 = if (is_dark) 58 else 66;
            rl.drawRectangleRec(field.tileRect(col, row), rl.Color.init(shade, shade + 6, shade + 14, 255));
        }
    }
}

fn gameRender(_: *Sys, scn: *Scene) void {
    drawStage();

    // Field, plus the line a block must not cross.
    rl.drawRectangleRec(field.rect, rl.fade(.black, 0.45));
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

        // The more damaged a block is, the darker it gets. Gold blocks are yellow.
        const left: f32 = @as(f32, @floatFromInt(health.current)) / @as(f32, @floatFromInt(@max(health.max, 1)));
        const shade: u8 = @intFromFloat(90.0 + 110.0 * std.math.clamp(left, 0.0, 1.0));
        const is_gold = scn.entities.getComponent(id, comps.Gold) != null;
        const color = if (is_gold) rl.Color.init(shade + 55, shade + 40, 0, 255) else rl.Color.init(shade, shade, shade, 255);
        const rect = rl.Rectangle{ .x = pos.x, .y = pos.y, .width = size.width, .height = size.height };
        rl.drawRectangleRec(rect, color);
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
        // Each kind of sphere has its own colour.
        const sphere = scn.entities.getComponent(id, comps.Sphere);
        const color = if (sphere) |s| spheres.info(s.kind).color else rl.Color.white;
        rl.drawCircleV(.{ .x = pos.x, .y = pos.y }, circle.radius, color);
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
