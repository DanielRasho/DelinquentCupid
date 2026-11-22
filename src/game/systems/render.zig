const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs");
const constants = @import("../constants.zig");
const comps = @import("../components.zig");
const field = @import("../field.zig");
const spheres = @import("../spheres.zig");
const sprites = @import("../sprites.zig");
const terrain = @import("../terrain.zig");
const ui = @import("../ui.zig");

const Sys = ecs.system.System;
const Scene = ecs.scene.Scene;

pub const render_system = Sys{ .render = gameRender };

const HEALTH_FONT_SIZE: i32 = 24;
/// The faces only leave their chin free for the health number: it goes in
/// the bottom of the block from this fraction of its height, at this size.
const CHIN_TOP: f32 = 0.74;
const CHIN_FONT_SIZE: i32 = 16;

const PLAYER_ANIM = sprites.Animation{
    .frames = &.{ .player_1, .player_2, .player_3, .player_4 },
    .fps = constants.PLAYER_ANIM_FPS,
};

// ===================
// RENDER: the greybox world (field, blocks, balls, player).
// ===================

/// The background map (`terrain.zig`), clipped to the stage: soil under
/// every cell first, so nothing is ever left empty, then the grass patches
/// over it, autotiled. While the blocks descend it slides down with them.
fn drawStage(scn: *Scene) void {
    var map_it = scn.entities.query(.{comps.Terrain});
    const map = scn.entities.getComponent(map_it.next() orelse return, comps.Terrain).?;
    var game_it = scn.entities.query(.{comps.Descent});
    const descent = scn.entities.getComponent(game_it.next() orelse return, comps.Descent).?;
    // Until `map.zig` has scrolled it for this descent, it has nothing to slide.
    const lag = if (map.scrolled) descent.lag() else 0;

    const stage = field.stage;
    rl.beginScissorMode(@intFromFloat(stage.x), @intFromFloat(stage.y), @intFromFloat(stage.width), @intFromFloat(stage.height));
    defer rl.endScissorMode();

    // The map's rows above the stage's top one start out of view.
    const tile = constants.TILE_SIZE;
    const top = stage.y - @as(f32, terrain.ROWS_ABOVE) * tile - lag;

    for (map.cells, 0..) |row, r| {
        const y = top + @as(f32, @floatFromInt(r)) * tile;
        for (row, 0..) |cell, c| {
            const soil = terrain.soilTile(cell.soil);
            sprites.drawTile(.map_soil, soil.col, soil.row, stage.x + @as(f32, @floatFromInt(c)) * tile, y);
        }
    }
    for (map.cells, 0..) |row, r| {
        const y = top + @as(f32, @floatFromInt(r)) * tile;
        for (row, 0..) |cell, c| {
            if (!cell.grass) continue;
            const grass = terrain.grassTile(terrain.grassMask(&map.cells, r, c));
            sprites.drawTile(.map_grass, grass.col, grass.row, stage.x + @as(f32, @floatFromInt(c)) * tile, y);
        }
    }
}

/// Clipped to the field: while the blocks descend, the new row slides in
/// from behind its top edge instead of over the wave counter above it.
fn drawBlocks(scn: *Scene) void {
    const area = field.rect;
    rl.beginScissorMode(@intFromFloat(area.x), @intFromFloat(area.y), @intFromFloat(area.width), @intFromFloat(area.height));
    defer rl.endScissorMode();

    var block_it = scn.entities.query(.{ comps.Block, comps.Position, comps.Size, comps.Health });
    while (block_it.next()) |id| {
        const block = scn.entities.getComponent(id, comps.Block).?;
        const pos = scn.entities.getComponent(id, comps.Position).?;
        const size = scn.entities.getComponent(id, comps.Size).?;
        const health = scn.entities.getComponent(id, comps.Health).?;
        if (health.current == 0) continue;

        // The art is a whole cell (or 2 x 2 for the boss): it covers the
        // `BLOCK_INSET` margin, so neighbouring blocks touch.
        const rect = rl.Rectangle{ .x = pos.x, .y = pos.y, .width = size.width, .height = size.height };
        sprites.drawCentered(block.art, rect);

        var buf: [16]u8 = undefined;
        const text = std.fmt.bufPrintZ(&buf, "{d}", .{health.current}) catch "?";
        const label = healthLabel(block.art, rect);
        ui.textInRect(text, label.area, label.size, .black);
    }
}

/// Where a block's health number goes: wherever its art leaves room. The
/// gold and boss art have an empty middle, the faces only their chin.
fn healthLabel(art: sprites.Sprite, rect: rl.Rectangle) struct { area: rl.Rectangle, size: i32 } {
    return switch (art) {
        .block_gold, .block_boss => .{ .area = rect, .size = HEALTH_FONT_SIZE },
        else => .{
            .area = .{
                .x = rect.x,
                .y = rect.y + rect.height * CHIN_TOP,
                .width = rect.width,
                .height = rect.height * (1.0 - CHIN_TOP),
            },
            .size = CHIN_FONT_SIZE,
        },
    };
}

fn gameRender(_: *Sys, scn: *Scene) void {
    drawStage(scn);

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

    drawBlocks(scn);

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
        const player = scn.entities.getComponent(id, comps.Player).?;
        const pos = scn.entities.getComponent(id, comps.Position).?;
        const half = constants.PLAYER_SIZE / 2.0;
        sprites.drawCentered(
            PLAYER_ANIM.frameAt(player.anim_time),
            .{ .x = pos.x - half, .y = pos.y - half, .width = constants.PLAYER_SIZE, .height = constants.PLAYER_SIZE },
        );
    }
}
