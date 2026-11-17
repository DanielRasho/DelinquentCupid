pub const SCREEN_W: f32 = 1024;
pub const SCREEN_H: f32 = 768;

// Scene names, as registered on `Game.instance` in main.zig.
pub const SCENE_GAME = "game";
pub const SCENE_LOSE = "lose";

// ===================
// FIELD (the grid the blocks live in)
// ===================
pub const GRID_COLS: u8 = 6;
pub const GRID_ROWS: u8 = 8;
pub const CELL_SIZE: f32 = 72;

pub const FIELD_W: f32 = CELL_SIZE * @as(f32, GRID_COLS);
pub const FIELD_H: f32 = CELL_SIZE * @as(f32, GRID_ROWS);
pub const FIELD_LEFT: f32 = (SCREEN_W - FIELD_W) / 2.0;
pub const FIELD_RIGHT: f32 = FIELD_LEFT + FIELD_W;
pub const FIELD_TOP: f32 = 56;
pub const FIELD_BOTTOM: f32 = FIELD_TOP + FIELD_H;

/// A block that descends into this row ends the run. It's the last row, so
/// the player always has one empty row of room to aim in.
pub const DANGER_ROW: u8 = GRID_ROWS - 1;

// ===================
// BLOCKS
// ===================
/// Empty margin around a block inside its cell (drawn and collided).
pub const BLOCK_INSET: f32 = 3;
/// Chance (0-100) that a cell of a freshly spawned row holds a block.
pub const BLOCK_FILL_CHANCE: i32 = 55;
/// Chance (0-100) that a new block gets twice the wave's health.
pub const BLOCK_DOUBLE_CHANCE: i32 = 15;
pub const BLOCK_HP_BASE: u32 = 1;
pub const BLOCK_HP_PER_TIER: u32 = 2;
pub const BLOCK_COIN_REWARD: u32 = 10;

/// Difficulty goes up one tier every `WAVES_PER_TIER` waves and stops
/// growing at `MAX_DIFFICULTY_WAVE`.
pub const WAVES_PER_TIER: u32 = 5;
pub const MAX_DIFFICULTY_WAVE: u32 = 60;

// ===================
// BALLS
// ===================
pub const BALL_RADIUS: f32 = 7;
/// A ball leaves at `BALL_SPEED_MIN` and gains the same amount of speed on
/// every block hit, reaching `BALL_SPEED_MAX` after `BALL_HITS_TO_MAX_SPEED`.
pub const BALL_SPEED_MAX: f32 = 900;
pub const BALL_SPEED_MIN: f32 = BALL_SPEED_MAX / 2.0;
pub const BALL_HITS_TO_MAX_SPEED: f32 = 7;
pub const BALL_DAMAGE: u32 = 1;
/// Seconds between two balls of the same volley leaving the player.
pub const BALL_LAUNCH_INTERVAL: f32 = 0.07;
pub const STARTING_BALLS: u32 = 3;

// ===================
// PLAYER / AIM
// ===================
pub const PLAYER_SIZE: f32 = 28;
/// Shallowest shot allowed, in radians above the horizontal. Bounces only
/// ever flip a velocity axis, so this also bounds how long a ball can stay up.
pub const AIM_MIN_ANGLE: f32 = 0.14;
/// How much of the path after the first bounce the aim ray previews.
pub const AIM_BOUNCE_LENGTH: f32 = 160;

// ===================
// SHOP
// ===================
pub const SHOP_SMALL_AMOUNT: u32 = 1;
pub const SHOP_SMALL_COST: u32 = 40;
pub const SHOP_BIG_AMOUNT: u32 = 6;
pub const SHOP_BIG_COST: u32 = 220;
