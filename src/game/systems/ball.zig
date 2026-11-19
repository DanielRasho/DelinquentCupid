const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs");
const constants = @import("../constants.zig");
const comps = @import("../components.zig");
const field = @import("../field.zig");
const spheres = @import("../spheres.zig");
const effects = @import("effects.zig");

const Sys = ecs.system.System;
const Scene = ecs.scene.Scene;
const EntityID = ecs.entity.EntityID;

// ===================
// BALLS
// ===================
pub const ball_system = Sys{ .update = ballUpdate, .destroy = ballDestroy };

fn ballDestroy(_: *Sys, scn: *Scene) void {
    var balls: std.ArrayList(EntityID) = .empty;
    defer balls.deinit(scn.allocator);

    var it = scn.entities.query(.{comps.Ball});
    while (it.next()) |id| {
        balls.append(scn.allocator, id) catch |err| std.debug.panic("ball destroy failed: {}", .{err});
    }
    for (balls.items) |id| scn.entities.remove(id);
}

/// Drives a volley: launches its balls one by one, flies them, and ends the
/// turn (`ADVANCING`) once every ball is back on the floor.
fn ballUpdate(_: *Sys, scn: *Scene, dt: f32) void {
    var game_it = scn.entities.query(.{comps.Turn});
    const game_id = game_it.next().?;
    if (scn.entities.getComponent(game_id, comps.Turn).?.phase != .FIRING) return;

    launch(scn, game_id, dt) catch |err| std.debug.panic("ball launch failed: {}", .{err});
    fly(scn, dt) catch |err| std.debug.panic("ball update failed: {}", .{err});

    const pending = scn.entities.getComponent(game_id, comps.Volley).?.pending.total();
    var left_it = scn.entities.query(.{comps.Ball});
    if (pending == 0 and left_it.next() == null) {
        scn.entities.getComponent(game_id, comps.Combo).?.hits = 0;
        scn.entities.getComponent(game_id, comps.Turn).?.phase = .ADVANCING;
    }
}

fn launch(scn: *Scene, game_id: EntityID, dt: f32) !void {
    // Spawning moves entities between archetypes, so work on a copy of the
    // volley and write it back at the end instead of holding a pointer.
    var volley = scn.entities.getComponent(game_id, comps.Volley).?.*;
    if (volley.pending.total() == 0) return;

    var player_it = scn.entities.query(.{ comps.Player, comps.Position });
    const player_x = scn.entities.getComponent(player_it.next().?, comps.Position).?.x;
    const origin = field.launchPoint(player_x);

    volley.cooldown -= dt;
    while (volley.pending.total() > 0 and volley.cooldown <= 0) {
        const id = try scn.entities.new();
        try scn.entities.setComponent(id, comps.Ball{});
        try scn.entities.setComponent(id, comps.Sphere{ .kind = takeRandom(&volley.pending) });
        try scn.entities.setComponent(id, comps.Position{ .x = origin.x, .y = origin.y });
        try scn.entities.setComponent(id, comps.Velocity{
            .x = volley.dir_x * constants.BALL_SPEED_MIN,
            .y = volley.dir_y * constants.BALL_SPEED_MIN,
        });
        try scn.entities.setComponent(id, comps.Circle{ .radius = constants.BALL_RADIUS });
        volley.cooldown += constants.BALL_LAUNCH_INTERVAL;
    }

    scn.entities.getComponent(game_id, comps.Volley).?.* = volley;
}

/// Takes one sphere out of `pending`, picked at random among those left so
/// the kinds come out mixed rather than in batches.
fn takeRandom(pending: *comps.BallStock) comps.SphereKind {
    var pick: u32 = @intCast(rl.getRandomValue(0, @intCast(pending.total() - 1)));
    for (std.enums.values(comps.SphereKind)) |kind| {
        const left = pending.of(kind);
        if (pick < left.*) {
            left.* -= 1;
            return kind;
        }
        pick -= left.*;
    }
    unreachable;
}

/// A special sphere's effect that went off: what kind, around which block.
const Struck = struct { kind: comps.SphereKind, hit: comps.GridCell };

fn fly(scn: *Scene, dt: f32) !void {
    // Balls that reached the floor; removed after the loop, never during it.
    var returned: std.ArrayList(EntityID) = .empty;
    defer returned.deinit(scn.allocator);
    // Effects that went off; their flashes are spawned after the loop too.
    var struck: std.ArrayList(Struck) = .empty;
    defer struck.deinit(scn.allocator);

    var it = scn.entities.query(.{ comps.Ball, comps.Sphere, comps.Position, comps.Velocity, comps.Circle });
    while (it.next()) |id| {
        const sphere = scn.entities.getComponent(id, comps.Sphere).?;
        const pos = scn.entities.getComponent(id, comps.Position).?;
        const vel = scn.entities.getComponent(id, comps.Velocity).?;
        const radius = scn.entities.getComponent(id, comps.Circle).?.radius;

        // Never travel more than one radius per step, so a fast ball (or a
        // long frame) can't tunnel through a block.
        const distance = @sqrt(vel.x * vel.x + vel.y * vel.y) * dt;
        const steps: usize = @intFromFloat(@max(1.0, @ceil(distance / radius)));
        const step_dt = dt / @as(f32, @floatFromInt(steps));

        for (0..steps) |_| {
            pos.x += vel.x * step_dt;
            pos.y += vel.y * step_dt;

            if (pos.x - radius <= constants.FIELD_LEFT) {
                pos.x = constants.FIELD_LEFT + radius;
                vel.x = @abs(vel.x);
            } else if (pos.x + radius >= constants.FIELD_RIGHT) {
                pos.x = constants.FIELD_RIGHT - radius;
                vel.x = -@abs(vel.x);
            }
            if (pos.y - radius <= constants.FIELD_TOP) {
                pos.y = constants.FIELD_TOP + radius;
                vel.y = @abs(vel.y);
            }

            if (vel.y > 0 and pos.y + radius >= constants.FIELD_BOTTOM) {
                markLanding(scn, pos.x);
                try returned.append(scn.allocator, id);
                break;
            }

            if (bounceOffBlocks(scn, sphere, pos, vel, radius)) |effect| try struck.append(scn.allocator, effect);
        }
    }

    for (returned.items) |id| scn.entities.remove(id);
    for (struck.items) |effect| try effects.flash(scn, effect.kind, effect.hit);
}

/// The first ball of a volley to land decides where the player goes next.
fn markLanding(scn: *Scene, x: f32) void {
    var it = scn.entities.query(.{comps.Player});
    const player = scn.entities.getComponent(it.next() orelse return, comps.Player).?;
    if (player.landed) return;
    player.landed = true;
    player.next_x = field.clampToFloor(x);
}

/// Bounces the ball off the block it overlaps the most (if any) and damages
/// it, plus the blocks around it when the sphere's effect goes off (returned
/// so its flash can be spawned). Only ever flips one velocity axis, so
/// |vel.y| never decays and every ball is guaranteed to come back down.
fn bounceOffBlocks(scn: *Scene, sphere: *comps.Sphere, pos: *comps.Position, vel: *comps.Velocity, radius: f32) ?Struck {
    var hit_id: ?EntityID = null;
    var hit_dist_sq: f32 = radius * radius;
    var hit_x: f32 = 0;
    var hit_y: f32 = 0;

    var it = scn.entities.query(.{ comps.Block, comps.Position, comps.Size, comps.Health });
    while (it.next()) |id| {
        if (scn.entities.getComponent(id, comps.Health).?.current == 0) continue;
        const block_pos = scn.entities.getComponent(id, comps.Position).?;
        const size = scn.entities.getComponent(id, comps.Size).?;

        // Closest point of the block to the ball's centre.
        const cx = std.math.clamp(pos.x, block_pos.x, block_pos.x + size.width);
        const cy = std.math.clamp(pos.y, block_pos.y, block_pos.y + size.height);
        const dist_sq = (pos.x - cx) * (pos.x - cx) + (pos.y - cy) * (pos.y - cy);
        if (dist_sq >= hit_dist_sq) continue;

        hit_id = id;
        hit_dist_sq = dist_sq;
        hit_x = cx;
        hit_y = cy;
    }

    const id = hit_id orelse return null;
    const dx = pos.x - hit_x;
    const dy = pos.y - hit_y;

    if (dx == 0 and dy == 0) {
        // The centre is inside the block: leave through the nearest face.
        const block_pos = scn.entities.getComponent(id, comps.Position).?;
        const size = scn.entities.getComponent(id, comps.Size).?;
        const to_left = pos.x - block_pos.x;
        const to_right = block_pos.x + size.width - pos.x;
        const to_top = pos.y - block_pos.y;
        const to_bottom = block_pos.y + size.height - pos.y;
        const nearest = @min(@min(to_left, to_right), @min(to_top, to_bottom));
        if (nearest == to_left) {
            pos.x = block_pos.x - radius;
            vel.x = -@abs(vel.x);
        } else if (nearest == to_right) {
            pos.x = block_pos.x + size.width + radius;
            vel.x = @abs(vel.x);
        } else if (nearest == to_top) {
            pos.y = block_pos.y - radius;
            vel.y = -@abs(vel.y);
        } else {
            pos.y = block_pos.y + size.height + radius;
            vel.y = @abs(vel.y);
        }
    } else if (@abs(dx) > @abs(dy)) {
        // Side hit: push out and send the ball away from the block.
        const side: f32 = if (dx > 0) 1 else -1;
        pos.x = hit_x + side * radius;
        vel.x = side * @abs(vel.x);
    } else {
        const side: f32 = if (dy > 0) 1 else -1;
        pos.y = hit_y + side * radius;
        vel.y = side * @abs(vel.y);
    }

    // Every hit hurts the block (harder with Strength cards) and charges
    // cupid's spirit meter.
    var game_it = scn.entities.query(.{comps.Turn});
    const game_id = game_it.next().?;
    const strength = scn.entities.getComponent(game_id, comps.Upgrades).?.strength;
    const damage = constants.BALL_DAMAGE + strength;
    const health = scn.entities.getComponent(id, comps.Health).?;
    health.current -|= damage;
    scn.entities.getComponent(game_id, comps.Combo).?.hits += 1;
    const spirit = scn.entities.getComponent(game_id, comps.Spirit).?;
    spirit.points = @min(spirit.points + constants.SPIRIT_PER_HIT, constants.SPIRIT_MAX);

    // Every block hit speeds the ball up a notch, up to the maximum. Scaling
    // the whole vector keeps its direction.
    const speed = @sqrt(vel.x * vel.x + vel.y * vel.y);
    const gain = (constants.BALL_SPEED_MAX - constants.BALL_SPEED_MIN) / constants.BALL_HITS_TO_MAX_SPEED;
    const scale = @min(speed + gain, constants.BALL_SPEED_MAX) / speed;
    vel.x *= scale;
    vel.y *= scale;

    const goes_off = spheres.goesOff(sphere.*);
    sphere.hits += 1;
    if (!goes_off) return null;
    const hit_cell = scn.entities.getComponent(id, comps.GridCell).?.*;
    setOff(scn, sphere.kind, id, hit_cell, damage);
    return .{ .kind = sphere.kind, .hit = hit_cell };
}

/// A special sphere's effect, from the block it hit (`hit_id`, covering
/// `hit`): every *other* live block the effect reaches takes the effect's
/// damage, once even if it's in several of its areas. Like the sphere's own
/// hit it only lowers `Health`; the block system removes what reaches 0.
/// It's not a hit itself: no combo, spirit or speed-up.
fn setOff(scn: *Scene, kind: comps.SphereKind, hit_id: EntityID, hit: comps.GridCell, sphere_damage: u32) void {
    const areas = spheres.effectAreas(kind, hit);
    const damage = spheres.effectDamage(kind, sphere_damage);

    var it = scn.entities.query(.{ comps.Block, comps.GridCell, comps.Health });
    while (it.next()) |id| {
        if (id == hit_id) continue;
        const health = scn.entities.getComponent(id, comps.Health).?;
        if (health.current == 0) continue;
        if (!areas.reach(scn.entities.getComponent(id, comps.GridCell).?.*)) continue;
        health.current -|= damage;
    }
}
