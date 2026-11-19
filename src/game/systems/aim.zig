const std = @import("std");
const rl = @import("raylib");
const zgui = @import("zgui");
const ecs = @import("ecs");
const constants = @import("../constants.zig");
const comps = @import("../components.zig");
const field = @import("../field.zig");

const Sys = ecs.system.System;
const Scene = ecs.scene.Scene;

// ===================
// AIM
// ===================
pub const aim_system = Sys{ .update = aimUpdate, .render = aimRender };

/// The previewed path: `origin` -> `end`, which is the first thing the ball
/// touches (`hits` set) or, if that's farther, `AIM_RAY_MAX_LENGTH` away.
const Aim = struct {
    origin: rl.Vector2,
    dir: rl.Vector2,
    end: rl.Vector2,
    hits: bool,
};

/// A left click inside the field fires the volley toward the cursor.
fn aimUpdate(_: *Sys, scn: *Scene, _: f32) void {
    var game_it = scn.entities.query(.{comps.Turn});
    const game_id = game_it.next().?;
    const turn = scn.entities.getComponent(game_id, comps.Turn).?;
    if (turn.phase != .AIMING) return;

    if (!rl.isMouseButtonPressed(.left)) return;
    // Clicks on the debug panels or outside the field (e.g. the shop) don't fire.
    if (zgui.io.getWantCaptureMouse()) return;
    if (!rl.checkCollisionPointRec(rl.getMousePosition(), field.rect)) return;

    const aim = computeAim(scn) orelse return;
    const stock = scn.entities.getComponent(game_id, comps.BallStock).?;
    scn.entities.getComponent(game_id, comps.Volley).?.* = .{
        .dir_x = aim.dir.x,
        .dir_y = aim.dir.y,
        .pending = stock.count,
        .cooldown = 0,
    };
    turn.phase = .FIRING;
}

fn aimRender(_: *Sys, scn: *Scene) void {
    var game_it = scn.entities.query(.{comps.Turn});
    const turn = scn.entities.getComponent(game_it.next() orelse return, comps.Turn).?;
    if (turn.phase != .AIMING) return;

    const aim = computeAim(scn) orelse return;
    rl.drawLineEx(aim.origin, aim.end, 2.0, .yellow);
    // The ghost ball only marks a real contact, not a line cut short.
    if (aim.hits) rl.drawCircleV(aim.end, constants.BALL_RADIUS, rl.fade(.yellow, 0.6));
}

fn computeAim(scn: *Scene) ?Aim {
    var player_it = scn.entities.query(.{ comps.Player, comps.Position });
    const player_pos = scn.entities.getComponent(player_it.next() orelse return null, comps.Position).?;
    const origin = field.launchPoint(player_pos.x);

    // Angle above the horizontal, clamped so the shot always goes up.
    const mouse = rl.getMousePosition();
    const raw = std.math.atan2(origin.y - mouse.y, mouse.x - origin.x);
    const angle = std.math.clamp(raw, constants.AIM_MIN_ANGLE, std.math.pi - constants.AIM_MIN_ANGLE);
    const dir = rl.Vector2{ .x = @cos(angle), .y = -@sin(angle) };

    const hit = castRay(scn, origin, dir);
    const hits = hit.t <= constants.AIM_RAY_MAX_LENGTH;
    const length = if (hits) hit.t else constants.AIM_RAY_MAX_LENGTH;
    return .{ .origin = origin, .dir = dir, .end = pointAt(origin, dir, length), .hits = hits };
}

fn pointAt(origin: rl.Vector2, dir: rl.Vector2, t: f32) rl.Vector2 {
    return .{ .x = origin.x + dir.x * t, .y = origin.y + dir.y * t };
}

const RayHit = struct { t: f32, normal: rl.Vector2 };

/// Smallest distance worth calling a hit; skips the surface a ray starts on.
const RAY_EPSILON: f32 = 0.01;

/// Casts the *centre* of a ball along `dir` (unit length) and returns the
/// first wall, floor or block it touches. Everything is grown by the ball's
/// radius, which is what makes a point ray stand in for the whole ball.
fn castRay(scn: *Scene, origin: rl.Vector2, dir: rl.Vector2) RayHit {
    const r = constants.BALL_RADIUS;
    var best = RayHit{ .t = std.math.inf(f32), .normal = .{ .x = 0, .y = 0 } };

    // The field's walls, ceiling and floor: we are inside this box.
    const left = constants.FIELD_LEFT + r;
    const right = constants.FIELD_RIGHT - r;
    const top = constants.FIELD_TOP + r;
    const bottom = constants.FIELD_BOTTOM - r;
    if (dir.x < 0) consider(&best, (left - origin.x) / dir.x, .{ .x = 1, .y = 0 });
    if (dir.x > 0) consider(&best, (right - origin.x) / dir.x, .{ .x = -1, .y = 0 });
    if (dir.y < 0) consider(&best, (top - origin.y) / dir.y, .{ .x = 0, .y = 1 });
    if (dir.y > 0) consider(&best, (bottom - origin.y) / dir.y, .{ .x = 0, .y = -1 });

    var it = scn.entities.query(.{ comps.Block, comps.Position, comps.Size, comps.Health });
    while (it.next()) |id| {
        if (scn.entities.getComponent(id, comps.Health).?.current == 0) continue;
        const pos = scn.entities.getComponent(id, comps.Position).?;
        const size = scn.entities.getComponent(id, comps.Size).?;
        const hit = castRayBox(origin, dir, .{
            .x = pos.x - r,
            .y = pos.y - r,
            .width = size.width + 2 * r,
            .height = size.height + 2 * r,
        }) orelse continue;
        consider(&best, hit.t, hit.normal);
    }

    // Can't happen from inside the field, but never hand back an infinite ray.
    if (best.t == std.math.inf(f32)) best.t = 0;
    return best;
}

fn consider(best: *RayHit, t: f32, normal: rl.Vector2) void {
    if (t > RAY_EPSILON and t < best.t) best.* = .{ .t = t, .normal = normal };
}

/// Slab test: where a ray enters `box` from outside, and through which face.
fn castRayBox(origin: rl.Vector2, dir: rl.Vector2, box: rl.Rectangle) ?RayHit {
    var t_enter: f32 = -std.math.inf(f32);
    var t_exit: f32 = std.math.inf(f32);
    var normal = rl.Vector2{ .x = 0, .y = 0 };

    const origins = [2]f32{ origin.x, origin.y };
    const dirs = [2]f32{ dir.x, dir.y };
    const lows = [2]f32{ box.x, box.y };
    const highs = [2]f32{ box.x + box.width, box.y + box.height };

    for (0..2) |axis| {
        if (dirs[axis] == 0) {
            if (origins[axis] < lows[axis] or origins[axis] > highs[axis]) return null;
            continue;
        }
        const t_low = (lows[axis] - origins[axis]) / dirs[axis];
        const t_high = (highs[axis] - origins[axis]) / dirs[axis];
        const t_near = @min(t_low, t_high);
        if (t_near > t_enter) {
            t_enter = t_near;
            // Entering through the low face when moving in +axis, the high one otherwise.
            const sign: f32 = if (dirs[axis] > 0) -1 else 1;
            normal = if (axis == 0) .{ .x = sign, .y = 0 } else .{ .x = 0, .y = sign };
        }
        t_exit = @min(t_exit, @max(t_low, t_high));
    }

    if (t_enter > t_exit) return null;
    return .{ .t = t_enter, .normal = normal };
}
