const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs");
const constants = @import("../constants.zig");
const comps = @import("../components.zig");
const field = @import("../field.zig");

const Sys = ecs.system.System;
const Scene = ecs.scene.Scene;
const EntityID = ecs.entity.EntityID;

// ===================
// BLOCKS
// ===================
pub const block_system = Sys{ .setup = blockSetup, .update = blockUpdate, .destroy = blockDestroy };

fn blockSetup(_: *Sys, scn: *Scene) void {
    // Game singleton must already exist (registered/set up before blocks).
    var game_it = scn.entities.query(.{comps.Turn});
    const wave = scn.entities.getComponent(game_it.next().?, comps.Turn).?.wave;
    spawnRow(scn, wave) catch |err| std.debug.panic("block setup failed: {}", .{err});
}

fn blockDestroy(_: *Sys, scn: *Scene) void {
    var blocks: std.ArrayList(EntityID) = .empty;
    defer blocks.deinit(scn.allocator);

    var it = scn.entities.query(.{comps.Block});
    while (it.next()) |id| {
        blocks.append(scn.allocator, id) catch |err| std.debug.panic("block destroy failed: {}", .{err});
    }
    for (blocks.items) |id| scn.entities.remove(id);
}

fn blockUpdate(_: *Sys, scn: *Scene, _: f32) void {
    var game_it = scn.entities.query(.{comps.Turn});
    const game_id = game_it.next().?;

    reapDead(scn, game_id) catch |err| std.debug.panic("block update failed: {}", .{err});

    if (scn.entities.getComponent(game_id, comps.Turn).?.phase != .ADVANCING) return;
    advance(scn, game_id) catch |err| std.debug.panic("block advance failed: {}", .{err});
}

/// Removes the blocks the balls brought down to zero and pays for each.
fn reapDead(scn: *Scene, game_id: EntityID) !void {
    var dead: std.ArrayList(EntityID) = .empty;
    defer dead.deinit(scn.allocator);

    var it = scn.entities.query(.{ comps.Block, comps.Health });
    while (it.next()) |id| {
        if (scn.entities.getComponent(id, comps.Health).?.current == 0) try dead.append(scn.allocator, id);
    }
    for (dead.items) |id| scn.entities.remove(id);

    const earned = @as(u32, @intCast(dead.items.len)) * constants.BLOCK_COIN_REWARD;
    scn.entities.getComponent(game_id, comps.Wallet).?.coins += earned;
}

/// End of a turn: every block drops one row, then either the run is lost or
/// the next wave's row comes in at the top.
fn advance(scn: *Scene, game_id: EntityID) !void {
    var reached_danger = false;

    var it = scn.entities.query(.{ comps.Block, comps.GridCell, comps.Position });
    while (it.next()) |id| {
        const cell = scn.entities.getComponent(id, comps.GridCell).?;
        cell.row += 1;
        if (cell.row >= constants.DANGER_ROW) reached_danger = true;

        const rect = field.blockRect(cell.col, cell.row);
        scn.entities.getComponent(id, comps.Position).?.* = .{ .x = rect.x, .y = rect.y };
    }

    const turn = scn.entities.getComponent(game_id, comps.Turn).?;
    if (reached_danger) {
        turn.phase = .LOST;
        return;
    }
    turn.wave += 1;
    turn.phase = .AIMING;

    // Spawning invalidates `turn`, so it's the last thing done here.
    try spawnRow(scn, turn.wave);
}

/// Health of a regular block spawned on `wave`: one step harder every
/// `WAVES_PER_TIER` waves, flat from `MAX_DIFFICULTY_WAVE` on.
fn blockHealth(wave: u32) u32 {
    const tier = @min(wave, constants.MAX_DIFFICULTY_WAVE) / constants.WAVES_PER_TIER;
    return constants.BLOCK_HP_BASE + tier * constants.BLOCK_HP_PER_TIER;
}

/// Fills the top row at random, always leaving at least one block and one gap.
fn spawnRow(scn: *Scene, wave: u32) !void {
    const cols = constants.GRID_COLS;
    var filled: [cols]bool = undefined;
    var count: usize = 0;
    for (&filled) |*cell| {
        cell.* = rl.getRandomValue(0, 99) < constants.BLOCK_FILL_CHANCE;
        if (cell.*) count += 1;
    }
    const forced: usize = @intCast(rl.getRandomValue(0, cols - 1));
    if (count == 0) filled[forced] = true;
    if (count == cols) filled[forced] = false;

    const base_health = blockHealth(wave);
    for (filled, 0..) |is_filled, col| {
        if (!is_filled) continue;
        const is_double = rl.getRandomValue(0, 99) < constants.BLOCK_DOUBLE_CHANCE;
        const health = if (is_double) base_health * 2 else base_health;
        const rect = field.blockRect(@intCast(col), 0);

        const id = try scn.entities.new();
        try scn.entities.setComponent(id, comps.Block{});
        try scn.entities.setComponent(id, comps.GridCell{ .col = @intCast(col), .row = 0 });
        try scn.entities.setComponent(id, comps.Position{ .x = rect.x, .y = rect.y });
        try scn.entities.setComponent(id, comps.Size{ .width = rect.width, .height = rect.height });
        try scn.entities.setComponent(id, comps.Health{ .current = health, .max = health });
    }
}
