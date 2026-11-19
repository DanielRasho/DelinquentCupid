const std = @import("std");
const constants = @import("constants.zig");

// ===================
// SPATIAL
// ===================

/// Top-left corner for things with a `Size`, centre for things with a `Circle`.
pub const Position = struct { x: f32, y: f32 };
pub const Velocity = struct { x: f32, y: f32 };
pub const Size = struct { width: f32, height: f32 };
pub const Circle = struct { radius: f32 };

// ===================
// BLOCKS
// ===================

pub const Block = struct {};
/// Where a block sits on the grid: (`col`, `row`) is its top-left cell and
/// it covers `cols` x `rows` cells (2 x 2 for a mini boss). `Position` and
/// `Size` are derived from it, so a future descent animation can ease
/// `Position` toward the cell.
pub const GridCell = struct { col: u8, row: u8, cols: u8 = 1, rows: u8 = 1 };
/// A block at `current == 0` is dead: balls ignore it and the block system
/// removes it (and pays out) on its next update.
pub const Health = struct { current: u32, max: u32 };
/// Love points a block pays when removed, before tarot bonuses.
pub const LoveReward = struct { points: u32 };
/// A gold block: pays more love points (the reward itself is in `LoveReward`).
pub const Gold = struct {};

// ===================
// BALLS / PLAYER
// ===================

pub const Ball = struct {};

/// The kinds of spirit sphere. All of them hit like a normal one; the
/// others also set off an effect around the block they hit (`spheres.zig`).
pub const SphereKind = enum { NORMAL, FIRE, BOMB, ROW_LASER, COLUMN_LASER, CROSS_LASER };

/// On every ball: its kind, and how many blocks it has hit so far (which
/// decides when its effect goes off again).
pub const Sphere = struct { kind: SphereKind = .NORMAL, hits: u32 = 0 };

/// `Position` is the centre of the player's cube; only x ever changes.
/// `next_x` is where the first ball of the current volley landed, valid
/// while `landed` is set; the player moves there once the volley is over.
pub const Player = struct { landed: bool = false, next_x: f32 = 0 };

// ===================
// SINGLETONS, all set on a single "game" entity.
// ===================

pub const Phase = enum {
    /// Waiting for the player to click a direction. The shop is open.
    AIMING,
    /// Balls are being launched and/or still flying.
    FIRING,
    /// Every ball came back: blocks descend and a new row spawns.
    ADVANCING,
    /// A tarot card was just dealt; waits for the player to dismiss it.
    TAROT,
    /// A block reached the danger row.
    LOST,
    /// The run reached the last wave.
    WON,
};
pub const Turn = struct { phase: Phase, wave: u32 };
/// The volley being fired: unit direction, the spheres still to launch (a
/// copy of `BallStock` taken on the click), and the time left until the
/// next one leaves.
pub const Volley = struct { dir_x: f32 = 0, dir_y: f32 = -1, pending: BallStock = .{}, cooldown: f32 = 0 };
/// How many spheres of each kind are owned; a volley launches all of them.
pub const BallStock = struct {
    normal: u32 = 0,
    fire: u32 = 0,
    bomb: u32 = 0,
    row_laser: u32 = 0,
    column_laser: u32 = 0,
    cross_laser: u32 = 0,

    pub fn of(self: *BallStock, kind: SphereKind) *u32 {
        return switch (kind) {
            .NORMAL => &self.normal,
            .FIRE => &self.fire,
            .BOMB => &self.bomb,
            .ROW_LASER => &self.row_laser,
            .COLUMN_LASER => &self.column_laser,
            .CROSS_LASER => &self.cross_laser,
        };
    }

    pub fn total(self: BallStock) u32 {
        var sum: u32 = 0;
        inline for (std.meta.fields(BallStock)) |f| sum += @field(self, f.name);
        return sum;
    }
};
/// Earned by removing blocks, spent on spheres.
pub const LovePoints = struct { points: u32 = 0 };
/// Earned by hitting blocks, spent on cupid's abilities. Capped at `SPIRIT_MAX`.
pub const Spirit = struct { points: u32 = 0 };

pub const Card = enum {
    /// Spheres deal +1 damage.
    STRENGTH,
    /// Blocks pay +50% love points.
    LOVERS,
    /// New blocks spawn weaker.
    TOWER,
};
/// How many of each card the run has collected.
pub const Upgrades = struct { strength: u32 = 0, lovers: u32 = 0, tower: u32 = 0 };
/// The cards offered during the `TAROT` phase (`dealt` once they've been drawn).
pub const TarotDraw = struct {
    dealt: bool = false,
    options: [constants.TAROT_OPTIONS]Card = @splat(.STRENGTH),
};
/// Block hits landed by the volley in flight; back to 0 when the turn ends.
pub const Combo = struct { hits: u32 = 0 };

// ===================
// EFFECTS
// ===================

/// A fading highlight over the cells a sphere's effect just struck. Its
/// rectangle is the entity's `Position` + `Size`. Owned by `effects.zig`.
pub const Flash = struct { kind: SphereKind, time_left: f32 };

// ===================
// GIRL (the portrait on the left reacts to what happens on the field)
// ===================

pub const Mood = enum { CALM, SCARED, HAPPY, SUPER_HAPPY, SUPER_SUPER_HAPPY };
/// `seen_points` is the love points total she last looked at, to notice gains.
pub const Girl = struct { mood: Mood = .CALM, happy_timer: f32 = 0, seen_points: u32 = 0 };

// ===================
// CINEMATIC (victory scene)
// ===================

pub const Cinematic = struct { elapsed: f32 = 0 };
