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
    spawnRow(scn, wave, 0) catch |err| std.debug.panic("block setup failed: {}", .{err});
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

fn blockUpdate(_: *Sys, scn: *Scene, dt: f32) void {
    var game_it = scn.entities.query(.{comps.Turn});
    const game_id = game_it.next().?;

    reapDead(scn, game_id) catch |err| std.debug.panic("block update failed: {}", .{err});

    if (scn.entities.getComponent(game_id, comps.Turn).?.phase != .ADVANCING) return;
    if (!scn.entities.getComponent(game_id, comps.Descent).?.started) {
        advance(scn, game_id) catch |err| std.debug.panic("block advance failed: {}", .{err});
    }
    descend(scn, game_id, dt);
}

/// Removes the blocks the balls brought down to zero and pays for each.
fn reapDead(scn: *Scene, game_id: EntityID) !void {
    var dead: std.ArrayList(EntityID) = .empty;
    defer dead.deinit(scn.allocator);

    var reward: u32 = 0;
    var it = scn.entities.query(.{ comps.Block, comps.Health, comps.LoveReward });
    while (it.next()) |id| {
        if (scn.entities.getComponent(id, comps.Health).?.current != 0) continue;
        reward += scn.entities.getComponent(id, comps.LoveReward).?.points;
        try dead.append(scn.allocator, id);
    }
    for (dead.items) |id| scn.entities.remove(id);

    // Each Lovers card adds half the base reward.
    const lovers = scn.entities.getComponent(game_id, comps.Upgrades).?.lovers;
    scn.entities.getComponent(game_id, comps.LovePoints).?.points += reward * (2 + lovers) / 2;
}

/// Start of the end-of-turn descent: every block drops one row on the grid
/// (`descend` then slides them there), and the turn's outcome is decided
/// now: the run is lost, won, or the next wave's row comes in at the top
/// (with a tarot card every few waves).
fn advance(scn: *Scene, game_id: EntityID) !void {
    var reached_danger = false;

    var it = scn.entities.query(.{ comps.Block, comps.GridCell });
    while (it.next()) |id| {
        const cell = scn.entities.getComponent(id, comps.GridCell).?;
        cell.row += 1;
        if (cell.row + cell.rows - 1 >= constants.DANGER_ROW) reached_danger = true;
    }

    const turn = scn.entities.getComponent(game_id, comps.Turn).?;
    const next: comps.Phase = outcome: {
        if (reached_danger) break :outcome .LOST;
        turn.wave += 1;
        if (turn.wave >= constants.WIN_WAVE) break :outcome .WON;
        break :outcome if (turn.wave % constants.TAROT_EVERY == 0) .TAROT else .AIMING;
    };
    scn.entities.getComponent(game_id, comps.Descent).?.* = .{ .started = true, .next = next };
    if (next == .LOST or next == .WON) return;

    // Spawning invalidates `turn`, so it's the last thing done here.
    const wave = turn.wave;
    const tower = scn.entities.getComponent(game_id, comps.Upgrades).?.tower;
    try spawnRow(scn, wave, tower);
}

/// Eases every block from one row above its cell down into it (the new row
/// slides in from above the field), in step with the player's walk. Once
/// it's over the turn moves on to the phase `advance` decided.
fn descend(scn: *Scene, game_id: EntityID, dt: f32) void {
    const descent = scn.entities.getComponent(game_id, comps.Descent).?;
    descent.time += dt;
    const lag = descent.lag();

    var it = scn.entities.query(.{ comps.Block, comps.GridCell, comps.Position });
    while (it.next()) |id| {
        const cell = scn.entities.getComponent(id, comps.GridCell).?;
        const rect = field.blockRect(cell.col, cell.row, cell.cols, cell.rows);
        scn.entities.getComponent(id, comps.Position).?.* = .{ .x = rect.x, .y = rect.y - lag };
    }

    if (descent.time < constants.BLOCK_DESCENT_TIME) return;
    scn.entities.getComponent(game_id, comps.Turn).?.phase = descent.next;
    descent.* = .{};
}

/// Health of a regular block spawned on `wave`: one step harder every
/// `WAVES_PER_TIER` waves, flat from `MAX_DIFFICULTY_WAVE` on. Each Tower
/// card (`tower`) shrinks it: x4/5, x4/6, x4/7...
fn blockHealth(wave: u32, tower: u32) u32 {
    const tier = @min(wave, constants.MAX_DIFFICULTY_WAVE) / constants.WAVES_PER_TIER;
    const curve = constants.BLOCK_HP_BASE + tier * constants.BLOCK_HP_PER_TIER;
    const health = (curve * constants.BLOCK_HP_PERCENT + 50) / 100; // rounded
    return @max(1, health * 4 / (4 + tower));
}

/// Percent chance (0-100) that a row spawned on `wave` brings a mini boss.
fn bossChance(wave: u32) i32 {
    if (wave < constants.BOSS_FIRST_WAVE) return 0;
    const progress = @min(wave, constants.BOSS_FULL_CHANCE_WAVE) - constants.BOSS_FIRST_WAVE;
    const span = constants.BOSS_FULL_CHANCE_WAVE - constants.BOSS_FIRST_WAVE;
    return @intCast(constants.BOSS_CHANCE_MAX * progress / span);
}

/// Fills the top row at random, always leaving at least one block and one
/// gap. Some regular blocks come out gold, and the row may bring a mini boss.
fn spawnRow(scn: *Scene, wave: u32, tower: u32) !void {
    const cols = constants.GRID_COLS;
    const base_health = blockHealth(wave, tower);

    // Columns of this row already taken by a mini boss.
    var taken: [cols]bool = @splat(false);
    if (rl.getRandomValue(0, 99) < bossChance(wave)) {
        if (bossColumn(scn)) |col| {
            @memset(taken[col..][0..constants.BOSS_COLS], true);
            try spawnBlock(scn, .{
                .col = col,
                .row = 0,
                .cols = constants.BOSS_COLS,
                .rows = constants.BOSS_ROWS,
            }, base_health * constants.BOSS_HP_MULTIPLIER, constants.BOSS_LOVE_REWARD, false);
        }
    }
    const has_boss = std.mem.indexOfScalar(bool, &taken, true) != null;

    // The guarantees below only ever touch the columns left free.
    var free: [cols]u8 = undefined;
    var free_count: usize = 0;
    var filled: [cols]bool = @splat(false);
    var filled_count: usize = 0;
    for (taken, 0..) |is_taken, col| {
        if (is_taken) continue;
        free[free_count] = @intCast(col);
        free_count += 1;
        filled[col] = rl.getRandomValue(0, 99) < constants.BLOCK_FILL_CHANCE;
        if (filled[col]) filled_count += 1;
    }
    const forced = free[@intCast(rl.getRandomValue(0, @intCast(free_count - 1)))];
    if (filled_count == 0 and !has_boss) filled[forced] = true;
    if (filled_count == free_count) filled[forced] = false;

    for (filled, 0..) |is_filled, col| {
        if (!is_filled) continue;
        const is_double = rl.getRandomValue(0, 99) < constants.BLOCK_DOUBLE_CHANCE;
        const is_gold = rl.getRandomValue(0, 99) < constants.GOLD_CHANCE;
        try spawnBlock(
            scn,
            .{ .col = @intCast(col), .row = 0 },
            if (is_double) base_health * 2 else base_health,
            if (is_gold) constants.GOLD_LOVE_REWARD else constants.BLOCK_LOVE_REWARD,
            is_gold,
        );
    }
}

/// A random left column for a mini boss on the new top row, or null if
/// there's no room. The boss reaches down into row 1, where the previous
/// wave's row just descended, so it needs `BOSS_COLS` side-by-side columns
/// that are free there.
fn bossColumn(scn: *Scene) ?u8 {
    const below = constants.BOSS_ROWS - 1;
    var blocked: [constants.GRID_COLS]bool = @splat(false);
    var it = scn.entities.query(.{ comps.Block, comps.GridCell });
    while (it.next()) |id| {
        const cell = scn.entities.getComponent(id, comps.GridCell).?;
        if (cell.row > below) continue;
        @memset(blocked[cell.col..][0..cell.cols], true);
    }

    var options: [constants.GRID_COLS]u8 = undefined;
    var total: usize = 0;
    for (0..constants.GRID_COLS - constants.BOSS_COLS + 1) |col| {
        if (std.mem.indexOfScalar(bool, blocked[col..][0..constants.BOSS_COLS], true) != null) continue;
        options[total] = @intCast(col);
        total += 1;
    }
    if (total == 0) return null;
    return options[@intCast(rl.getRandomValue(0, @intCast(total - 1)))];
}

fn spawnBlock(scn: *Scene, cell: comps.GridCell, health: u32, reward: u32, gold: bool) !void {
    const rect = field.blockRect(cell.col, cell.row, cell.cols, cell.rows);
    const id = try scn.entities.new();
    try scn.entities.setComponent(id, comps.Block{});
    try scn.entities.setComponent(id, cell);
    try scn.entities.setComponent(id, comps.Position{ .x = rect.x, .y = rect.y });
    try scn.entities.setComponent(id, comps.Size{ .width = rect.width, .height = rect.height });
    try scn.entities.setComponent(id, comps.Health{ .current = health, .max = health });
    try scn.entities.setComponent(id, comps.LoveReward{ .points = reward });
    if (gold) try scn.entities.setComponent(id, comps.Gold{});
}
