const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs");
const constants = @import("../constants.zig");
const comps = @import("../components.zig");
const ui = @import("../ui.zig");

const Sys = ecs.system.System;
const Scene = ecs.scene.Scene;

// ===================
// CUPID: the right column. A portrait that heats up with the spirit meter,
// the meter itself, and the abilities it pays for (only between turns).
// ===================
pub const cupid_system = Sys{ .update = cupidUpdate, .render = cupidRender };

const Effect = enum { INTIMIDATION, KABEDON, ORA };
const Ability = struct { name: [:0]const u8, cost: u32, effect: Effect };

const ABILITIES = [_]Ability{
    .{ .name = "Intimidation", .cost = constants.INTIMIDATION_COST, .effect = .INTIMIDATION },
    .{ .name = "Kabedon", .cost = constants.KABEDON_COST, .effect = .KABEDON },
    .{ .name = "ORA ORA ORA ORA", .cost = constants.ORA_COST, .effect = .ORA },
};

const X: f32 = constants.RIGHT_COLUMN_X;
const W: f32 = constants.COLUMN_CONTENT_W;
const PORTRAIT = rl.Rectangle{ .x = X, .y = constants.PORTRAIT_Y, .width = W, .height = constants.PORTRAIT_H };
const METER = rl.Rectangle{ .x = X, .y = constants.COLUMN_BODY_Y, .width = W, .height = 28 };
const METER_LABEL_Y: f32 = METER.y + METER.height + 8;
const BUTTONS_Y: f32 = METER_LABEL_Y + 36;
const BUTTON_H: f32 = 52;
const BUTTON_GAP: f32 = 12;

fn buttonRect(index: usize) rl.Rectangle {
    return .{ .x = X, .y = BUTTONS_Y + @as(f32, @floatFromInt(index)) * (BUTTON_H + BUTTON_GAP), .width = W, .height = BUTTON_H };
}

fn cupidUpdate(_: *Sys, scn: *Scene, _: f32) void {
    var game_it = scn.entities.query(.{comps.Turn});
    const game_id = game_it.next().?;
    if (scn.entities.getComponent(game_id, comps.Turn).?.phase != .AIMING) return;
    if (!ui.clicked()) return;

    const spirit = scn.entities.getComponent(game_id, comps.Spirit).?;
    for (ABILITIES, 0..) |ability, i| {
        if (!rl.checkCollisionPointRec(rl.getMousePosition(), buttonRect(i))) continue;
        if (spirit.points < ability.cost) return;
        spirit.points -= ability.cost;
        cast(scn, ability.effect);
        return;
    }
}

/// Abilities only lower `Health`; blocks left at 0 are removed (and paid
/// for) by the block system, exactly like blocks killed by spheres.
fn cast(scn: *Scene, effect: Effect) void {
    switch (effect) {
        .INTIMIDATION => strike(scn, nearestRows(scn, constants.INTIMIDATION_ROWS), null, constants.INTIMIDATION_PERCENT),
        .KABEDON => strike(scn, null, randomColumns(scn, constants.KABEDON_COLUMNS), constants.KABEDON_PERCENT),
        .ORA => strike(scn, nearestRows(scn, constants.ORA_ROWS), null, 100),
    }
}

const RowMask = [constants.GRID_ROWS]bool;
const ColumnMask = [constants.GRID_COLS]bool;

/// Removes `percent` of the *max* health (at least 1) of every block in the
/// selected rows and columns; a null mask selects all of them.
fn strike(scn: *Scene, rows: ?RowMask, columns: ?ColumnMask, percent: u32) void {
    var it = scn.entities.query(.{ comps.Block, comps.GridCell, comps.Health });
    while (it.next()) |id| {
        // A block bigger than one cell is hit if any of its rows/columns is selected.
        const cell = scn.entities.getComponent(id, comps.GridCell).?;
        if (rows) |mask| if (!anySelected(&mask, cell.row, cell.rows)) continue;
        if (columns) |mask| if (!anySelected(&mask, cell.col, cell.cols)) continue;

        const health = scn.entities.getComponent(id, comps.Health).?;
        health.current -|= @max(1, (health.max * percent + 99) / 100);
    }
}

fn anySelected(mask: []const bool, start: u8, len: u8) bool {
    return std.mem.indexOfScalar(bool, mask[start..][0..len], true) != null;
}

/// The `count` rows closest to the player that still have a block in them.
fn nearestRows(scn: *Scene, count: u8) RowMask {
    var occupied = [_]bool{false} ** constants.GRID_ROWS;
    var it = scn.entities.query(.{ comps.Block, comps.GridCell, comps.Health });
    while (it.next()) |id| {
        if (scn.entities.getComponent(id, comps.Health).?.current == 0) continue;
        const cell = scn.entities.getComponent(id, comps.GridCell).?;
        @memset(occupied[cell.row..][0..cell.rows], true);
    }

    var picked = [_]bool{false} ** constants.GRID_ROWS;
    var left = count;
    var row: usize = constants.GRID_ROWS;
    while (row > 0 and left > 0) {
        row -= 1;
        if (!occupied[row]) continue;
        picked[row] = true;
        left -= 1;
    }
    return picked;
}

/// Up to `count` columns picked at random among those that have a block.
fn randomColumns(scn: *Scene, count: u8) ColumnMask {
    var occupied = [_]bool{false} ** constants.GRID_COLS;
    var it = scn.entities.query(.{ comps.Block, comps.GridCell, comps.Health });
    while (it.next()) |id| {
        if (scn.entities.getComponent(id, comps.Health).?.current == 0) continue;
        const cell = scn.entities.getComponent(id, comps.GridCell).?;
        @memset(occupied[cell.col..][0..cell.cols], true);
    }

    var candidates: [constants.GRID_COLS]usize = undefined;
    var total: usize = 0;
    for (occupied, 0..) |is_occupied, col| {
        if (!is_occupied) continue;
        candidates[total] = col;
        total += 1;
    }

    // Partial shuffle: the first `count` entries end up a random sample.
    var picked = [_]bool{false} ** constants.GRID_COLS;
    for (0..@min(count, total)) |i| {
        const j: usize = @intCast(rl.getRandomValue(@intCast(i), @intCast(total - 1)));
        std.mem.swap(usize, &candidates[i], &candidates[j]);
        picked[candidates[i]] = true;
    }
    return picked;
}

fn cupidRender(_: *Sys, scn: *Scene) void {
    var game_it = scn.entities.query(.{comps.Turn});
    const game_id = game_it.next() orelse return;
    const open = scn.entities.getComponent(game_id, comps.Turn).?.phase == .AIMING;
    const points = scn.entities.getComponent(game_id, comps.Spirit).?.points;

    // The fuller the meter, the angrier he looks.
    const third = constants.SPIRIT_MAX / 3;
    if (points < third) {
        ui.placeholder(PORTRAIT, "CUPID: chill", .sky_blue);
    } else if (points < 2 * third) {
        ui.placeholder(PORTRAIT, "CUPID: fired up", .orange);
    } else {
        ui.placeholder(PORTRAIT, "CUPID: furious", .red);
    }

    const filled: f32 = @as(f32, @floatFromInt(points)) / @as(f32, @floatFromInt(constants.SPIRIT_MAX));
    rl.drawRectangleRec(METER, rl.fade(.black, 0.4));
    rl.drawRectangleRec(.{ .x = METER.x, .y = METER.y, .width = METER.width * filled, .height = METER.height }, .lime);
    rl.drawRectangleLinesEx(METER, 2.0, .light_gray);

    var buf: [64]u8 = undefined;
    const label = ui.format(&buf, "Spirit Meter  {d}/{d}", .{ points, constants.SPIRIT_MAX });
    ui.textCentered(label, X + W / 2.0, METER_LABEL_Y, 20, .ray_white);

    for (ABILITIES, 0..) |ability, i| {
        const text = ui.format(&buf, "{s} ({d})", .{ ability.name, ability.cost });
        ui.button(buttonRect(i), text, 18, open and points >= ability.cost);
    }
}
