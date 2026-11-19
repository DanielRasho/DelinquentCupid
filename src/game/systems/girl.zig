const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs");
const constants = @import("../constants.zig");
const comps = @import("../components.zig");
const ui = @import("../ui.zig");

const Sys = ecs.system.System;
const Scene = ecs.scene.Scene;

// ===================
// GIRL: the portrait at the top of the left column. Its mood follows the
// field; for now a mood is just a colour and a label.
// ===================
pub const girl_system = Sys{ .setup = girlSetup, .update = girlUpdate, .render = girlRender, .destroy = girlDestroy };

const PORTRAIT = rl.Rectangle{
    .x = constants.LEFT_COLUMN_X,
    .y = constants.PORTRAIT_Y,
    .width = constants.COLUMN_CONTENT_W,
    .height = constants.PORTRAIT_H,
};

fn girlSetup(_: *Sys, scn: *Scene) void {
    spawnGirl(scn) catch |err| std.debug.panic("girl setup failed: {}", .{err});
}
fn spawnGirl(scn: *Scene) !void {
    const id = try scn.entities.new();
    try scn.entities.setComponent(id, comps.Girl{});
}
fn girlDestroy(_: *Sys, scn: *Scene) void {
    var it = scn.entities.query(.{comps.Girl});
    if (it.next()) |id| scn.entities.remove(id);
}

/// Happier and happier as the volley's combo grows, happy for a moment
/// whenever love points come in, scared while the crowd is about to reach
/// her, calm otherwise.
fn girlUpdate(_: *Sys, scn: *Scene, dt: f32) void {
    var girl_it = scn.entities.query(.{comps.Girl});
    const girl = scn.entities.getComponent(girl_it.next() orelse return, comps.Girl).?;

    var game_it = scn.entities.query(.{comps.LovePoints});
    const game_id = game_it.next().?;
    const points = scn.entities.getComponent(game_id, comps.LovePoints).?.points;
    const combo = scn.entities.getComponent(game_id, comps.Combo).?.hits;
    if (points > girl.seen_points) girl.happy_timer = constants.GIRL_HAPPY_TIME;
    girl.seen_points = points;
    girl.happy_timer = @max(0, girl.happy_timer - dt);

    var crowd_is_close = false;
    var block_it = scn.entities.query(.{ comps.Block, comps.GridCell, comps.Health });
    while (block_it.next()) |id| {
        if (scn.entities.getComponent(id, comps.Health).?.current == 0) continue;
        const cell = scn.entities.getComponent(id, comps.GridCell).?;
        const bottom_row = cell.row + cell.rows - 1;
        if (bottom_row + constants.GIRL_SCARED_ROWS >= constants.DANGER_ROW) crowd_is_close = true;
    }

    girl.mood = if (combo >= constants.GIRL_SUPER_SUPER_HAPPY_HITS)
        .SUPER_SUPER_HAPPY
    else if (combo >= constants.GIRL_SUPER_HAPPY_HITS)
        .SUPER_HAPPY
    else if (combo >= constants.GIRL_HAPPY_HITS or girl.happy_timer > 0)
        .HAPPY
    else if (crowd_is_close)
        .SCARED
    else
        .CALM;
}

fn girlRender(_: *Sys, scn: *Scene) void {
    var it = scn.entities.query(.{comps.Girl});
    const girl = scn.entities.getComponent(it.next() orelse return, comps.Girl).?;
    switch (girl.mood) {
        .CALM => ui.placeholder(PORTRAIT, "GIRL: calm", .pink),
        .SCARED => ui.placeholder(PORTRAIT, "GIRL: scared", .violet),
        .HAPPY => ui.placeholder(PORTRAIT, "GIRL: happy", .gold),
        .SUPER_HAPPY => ui.placeholder(PORTRAIT, "GIRL: super happy", .orange),
        .SUPER_SUPER_HAPPY => ui.placeholder(PORTRAIT, "GIRL: super super happy", .magenta),
    }
}
