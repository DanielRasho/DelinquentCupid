const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs");
const constants = @import("../constants.zig");
const comps = @import("../components.zig");
const field = @import("../field.zig");
const spheres = @import("../spheres.zig");

const Sys = ecs.system.System;
const Scene = ecs.scene.Scene;
const EntityID = ecs.entity.EntityID;

// ===================
// EFFECTS: the flash over the cells a special sphere's effect struck. The
// ball system calls `flash` when an effect goes off; from there this system
// owns the flashes: fades them out, draws them over the field, removes them.
// ===================
pub const effects_system = Sys{ .update = effectsUpdate, .render = effectsRender, .destroy = effectsDestroy };

/// Spawns one flash per area `kind`'s effect strikes around the block at
/// `hit`. Spawning moves entities between archetypes: never call it while
/// iterating a query.
pub fn flash(scn: *Scene, kind: comps.SphereKind, hit: comps.GridCell) !void {
    const areas = spheres.effectAreas(kind, hit);
    for (areas.slice()) |area| {
        const cells = spheres.clipToGrid(area) orelse continue;
        const rect = field.blockRect(@intCast(cells.col), @intCast(cells.row), @intCast(cells.cols), @intCast(cells.rows));
        const id = try scn.entities.new();
        try scn.entities.setComponent(id, comps.Flash{ .kind = kind, .time_left = constants.EFFECT_FLASH_TIME });
        try scn.entities.setComponent(id, comps.Position{ .x = rect.x, .y = rect.y });
        try scn.entities.setComponent(id, comps.Size{ .width = rect.width, .height = rect.height });
    }
}

fn effectsDestroy(_: *Sys, scn: *Scene) void {
    removeFlashes(scn, null) catch |err| std.debug.panic("effects destroy failed: {}", .{err});
}

fn effectsUpdate(_: *Sys, scn: *Scene, dt: f32) void {
    removeFlashes(scn, dt) catch |err| std.debug.panic("effects update failed: {}", .{err});
}

/// Ages every flash by `dt` and removes the ones that ran out; a null `dt`
/// removes them all.
fn removeFlashes(scn: *Scene, dt: ?f32) !void {
    var expired: std.ArrayList(EntityID) = .empty;
    defer expired.deinit(scn.allocator);

    var it = scn.entities.query(.{comps.Flash});
    while (it.next()) |id| {
        const flash_comp = scn.entities.getComponent(id, comps.Flash).?;
        if (dt) |step| flash_comp.time_left -= step;
        if (dt == null or flash_comp.time_left <= 0) try expired.append(scn.allocator, id);
    }
    for (expired.items) |id| scn.entities.remove(id);
}

fn effectsRender(_: *Sys, scn: *Scene) void {
    var it = scn.entities.query(.{ comps.Flash, comps.Position, comps.Size });
    while (it.next()) |id| {
        const flash_comp = scn.entities.getComponent(id, comps.Flash).?;
        const pos = scn.entities.getComponent(id, comps.Position).?;
        const size = scn.entities.getComponent(id, comps.Size).?;

        const left = std.math.clamp(flash_comp.time_left / constants.EFFECT_FLASH_TIME, 0.0, 1.0);
        const color = spheres.info(flash_comp.kind).color;
        const rect = rl.Rectangle{ .x = pos.x, .y = pos.y, .width = size.width, .height = size.height };
        rl.drawRectangleRec(rect, rl.fade(color, 0.45 * left));
        rl.drawRectangleLinesEx(rect, 3.0, rl.fade(color, left));
    }
}
