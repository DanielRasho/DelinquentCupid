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
/// Where a block sits on the grid. `Position` is derived from it, so a
/// future descent animation can ease `Position` toward the cell.
pub const GridCell = struct { col: u8, row: u8 };
/// A block at `current == 0` is dead: balls ignore it and the block system
/// removes it (and pays out) on its next update.
pub const Health = struct { current: u32, max: u32 };

// ===================
// BALLS / PLAYER
// ===================

pub const Ball = struct {};

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
    /// A block reached the danger row.
    LOST,
};
pub const Turn = struct { phase: Phase, wave: u32 };
/// The volley being fired: unit direction, balls still to launch, and the
/// time left until the next one leaves.
pub const Volley = struct { dir_x: f32 = 0, dir_y: f32 = -1, pending: u32 = 0, cooldown: f32 = 0 };
/// How many balls a volley launches.
pub const BallStock = struct { count: u32 };
pub const Wallet = struct { coins: u32 };
