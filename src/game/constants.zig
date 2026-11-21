pub const SCREEN_W: f32 = 1500;
pub const SCREEN_H: f32 = 768;

// Scene names, as registered on `Game.instance` in main.zig.
pub const SCENE_MENU = "menu";
pub const SCENE_GAME = "game";
pub const SCENE_WIN = "win";
pub const SCENE_LOSE = "lose";

/// Reaching this wave wins the run.
pub const WIN_WAVE: u32 = 100;

// ===================
// LAYOUT: [ left column | stage | right column ]
// ===================
/// Side of a square tile of the stage's tileset. One block fills one tile.
pub const TILE_SIZE: f32 = 72;

/// Full width of each side column. THE knob for how much room the stage
/// gets: the stage is whatever the two columns leave free. The stage is a
/// whole number of tiles wide when `SCREEN_W - 2 * COLUMN_W` is a multiple
/// of `TILE_SIZE` (1500 - 2 * 318 = 864 = 12 tiles).
pub const COLUMN_W: f32 = 318;
/// Empty space between a column's edge and its widgets.
pub const COLUMN_PADDING: f32 = 12;
pub const COLUMN_CONTENT_W: f32 = COLUMN_W - 2 * COLUMN_PADDING;
pub const LEFT_COLUMN_X: f32 = COLUMN_PADDING;
pub const RIGHT_COLUMN_X: f32 = SCREEN_W - COLUMN_W + COLUMN_PADDING;
pub const PORTRAIT_Y: f32 = 12;
pub const PORTRAIT_H: f32 = 200;
/// Where the widgets under a portrait start.
pub const COLUMN_BODY_Y: f32 = PORTRAIT_Y + PORTRAIT_H + 16;

/// The stage: the area between the columns where the game art (tilemap) goes.
pub const STAGE_X: f32 = COLUMN_W;
pub const STAGE_W: f32 = SCREEN_W - 2 * COLUMN_W;

// ===================
// FIELD (the grid the blocks live in, centred on the stage)
// ===================
pub const GRID_COLS: u8 = 6;
pub const GRID_ROWS: u8 = 8;
pub const CELL_SIZE: f32 = TILE_SIZE;

pub const FIELD_W: f32 = CELL_SIZE * @as(f32, GRID_COLS);
pub const FIELD_H: f32 = CELL_SIZE * @as(f32, GRID_ROWS);
pub const FIELD_LEFT: f32 = STAGE_X + (STAGE_W - FIELD_W) / 2.0;
pub const FIELD_RIGHT: f32 = FIELD_LEFT + FIELD_W;
/// One tile of room above the field (the wave counter lives there).
pub const FIELD_TOP: f32 = TILE_SIZE;
pub const FIELD_BOTTOM: f32 = FIELD_TOP + FIELD_H;

comptime {
    if (STAGE_W < FIELD_W) @compileError("COLUMN_W leaves no room for the field: shrink it or widen SCREEN_W");
}

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
/// Global health multiplier, in percent, applied on top of the curve above.
pub const BLOCK_HP_PERCENT: u32 = 125;
/// Love points earned per block removed (before tarot bonuses).
pub const BLOCK_LOVE_REWARD: u32 = 10;

/// Chance (0-100) that a regular block spawns as a gold one.
pub const GOLD_CHANCE: i32 = 10;
pub const GOLD_LOVE_REWARD: u32 = 30;

/// Mini bosses: 2 x 2 blocks, at most one per spawned row. Their chance
/// grows linearly from 0 at `BOSS_FIRST_WAVE` up to `BOSS_CHANCE_MAX`
/// (0-100) at `BOSS_FULL_CHANCE_WAVE`, and stays there.
pub const BOSS_COLS: u8 = 2;
pub const BOSS_ROWS: u8 = 2;
pub const BOSS_CHANCE_MAX: u32 = 15;
pub const BOSS_FIRST_WAVE: u32 = 5;
pub const BOSS_FULL_CHANCE_WAVE: u32 = 40;
/// A boss has this many times the health of a regular block of its wave.
pub const BOSS_HP_MULTIPLIER: u32 = 4;
pub const BOSS_LOVE_REWARD: u32 = 40;

comptime {
    if (BOSS_FULL_CHANCE_WAVE <= BOSS_FIRST_WAVE) @compileError("BOSS_FULL_CHANCE_WAVE must come after BOSS_FIRST_WAVE");
    // Bosses spawn on the top rows and need a gap beside them in their row.
    if (BOSS_COLS >= GRID_COLS or BOSS_ROWS >= DANGER_ROW) @compileError("mini boss doesn't fit the grid");
}

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
pub const BALL_SPEED_MAX: f32 = 1800;
pub const BALL_SPEED_MIN: f32 = 1800;
pub const BALL_HITS_TO_MAX_SPEED: f32 = 7;
pub const BALL_DAMAGE: u32 = 1;
/// Seconds between two balls of the same volley leaving the player.
pub const BALL_LAUNCH_INTERVAL: f32 = 0.07;
/// Normal spheres a run starts with.
pub const STARTING_BALLS: u32 = 1;

// ===================
// SPHERE KINDS (what the shop rolls; see `spheres.zig`)
// ===================
/// Chance (0-100) that a bought sphere comes out as each kind.
pub const NORMAL_SPHERE_CHANCE: u32 = 60;
pub const FIRE_SPHERE_CHANCE: u32 = 8;
pub const BOMB_SPHERE_CHANCE: u32 = 8;
pub const ROW_LASER_CHANCE: u32 = 8;
pub const COLUMN_LASER_CHANCE: u32 = 8;
pub const CROSS_LASER_CHANCE: u32 = 8;

/// A special sphere's effect goes off on its first block hit and then on
/// every this-many hits after (with 2: the 1st, 3rd, 5th... hit).
pub const FIRE_EVERY: u32 = 2;
pub const BOMB_EVERY: u32 = 2;
pub const ROW_LASER_EVERY: u32 = 3;
pub const COLUMN_LASER_EVERY: u32 = 3;
pub const CROSS_LASER_EVERY: u32 = 3;

/// What fire deals to each block next to the one hit. Flat: Strength cards
/// don't add to it. Bombs and lasers deal the sphere's own damage instead.
pub const FIRE_DAMAGE: u32 = 1;
/// How long the flash over the cells an effect struck stays on screen.
pub const EFFECT_FLASH_TIME: f32 = 0.3;

comptime {
    const total = NORMAL_SPHERE_CHANCE + FIRE_SPHERE_CHANCE + BOMB_SPHERE_CHANCE +
        ROW_LASER_CHANCE + COLUMN_LASER_CHANCE + CROSS_LASER_CHANCE;
    if (total != 100) @compileError("sphere chances must add up to 100");
    if (@min(FIRE_EVERY, BOMB_EVERY, ROW_LASER_EVERY, COLUMN_LASER_EVERY, CROSS_LASER_EVERY) == 0)
        @compileError("a sphere effect can't go off every 0 hits");
}

// ===================
// PLAYER / AIM
// ===================
pub const PLAYER_SIZE: f32 = 28;
/// Seconds the player takes to walk (easing in and out) to where the
/// volley's first ball landed. No aiming until the walk is over.
pub const PLAYER_WALK_TIME: f32 = 1;
/// Seconds the blocks take to slide one row down at the end of a turn
/// (same easing as the walk, and starting on the same frame). Matching
/// the walk keeps both moving in lockstep. No aiming until it's over.
pub const BLOCK_DESCENT_TIME: f32 = PLAYER_WALK_TIME;

comptime {
    if (BLOCK_DESCENT_TIME <= 0) @compileError("BLOCK_DESCENT_TIME must be positive");
}
/// Shallowest shot allowed, in radians above the horizontal. Bounces only
/// ever flip a velocity axis, so this also bounds how long a ball can stay up.
pub const AIM_MIN_ANGLE: f32 = 0.14;
/// Longest the aim preview line gets, in pixels (one cell is `CELL_SIZE` = 72).
/// It still stops early at the first wall or block it touches.
pub const AIM_RAY_MAX_LENGTH: f32 = 300;

// ===================
// SHOP (love points -> spheres)
// ===================
pub const SPHERE_COST: u32 = 40;

// ===================
// GIRL
// ===================
/// How long she stays happy after love points come in.
pub const GIRL_HAPPY_TIME: f32 = 0.8;
/// She gets scared once a block is this many rows (or fewer) from the danger row.
pub const GIRL_SCARED_ROWS: u8 = 2;
/// Block hits in a single volley (the combo) that make her happy, super
/// happy and super super happy.
pub const GIRL_HAPPY_HITS: u32 = 5;
pub const GIRL_SUPER_HAPPY_HITS: u32 = 15;
pub const GIRL_SUPER_SUPER_HAPPY_HITS: u32 = 30;

// ===================
// CUPID (spirit meter + abilities)
// ===================
pub const SPIRIT_MAX: u32 = 100;
/// Spirit points earned every time a sphere hits a block.
pub const SPIRIT_PER_HIT: u32 = 1;

pub const INTIMIDATION_COST: u32 = 30;
pub const INTIMIDATION_ROWS: u8 = 3;
/// Percent of each block's *max* health removed.
pub const INTIMIDATION_PERCENT: u32 = 25;

pub const KABEDON_COST: u32 = 50;
pub const KABEDON_COLUMNS: u8 = 3;
pub const KABEDON_PERCENT: u32 = 50;

pub const ORA_COST: u32 = 80;
pub const ORA_ROWS: u8 = 2;

// ===================
// TAROT
// ===================
/// Cards are offered every time the wave number hits a multiple of this.
pub const TAROT_EVERY: u32 = 10;
/// How many cards the player picks one from.
pub const TAROT_OPTIONS: usize = 3;
