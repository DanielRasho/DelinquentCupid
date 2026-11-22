//! Raw bytes of every sprite PNG, embedded at build time. This file is the
//! root of the `sprite_files` module (see build.zig): `@embedFile` can't leave
//! its module's directory, so the module has to live next to the art.
//!
//! Each name here must match a field of `Sprite` in `src/game/sprites.zig`,
//! which decodes these into textures. Adding a sprite = one line here + one
//! enum field there.

// The game logo (260 x 120): main menu, victory and lose screens.
pub const logo = @embedFile("Logo.png");

// Mika, one portrait per `Mood`.
pub const mika_neutral = @embedFile("mika/neutral.png");
pub const mika_scared = @embedFile("mika/Scared.png");
pub const mika_happy = @embedFile("mika/happy.png");
pub const mika_super_happy = @embedFile("mika/superHappy.png");
pub const mika_ecstatic = @embedFile("mika/Ecstatic.png");

// Cupid, one portrait per third of the spirit meter.
pub const cupid_chill = @embedFile("cupid/chill.png");
pub const cupid_motivated = @embedFile("cupid/motivated.png");
pub const cupid_fired_up = @embedFile("cupid/firedUp.png");

// Map tile sheets, 4 x 4 tiles of 32 x 32: grass autotiles (layout in
// `src/game/terrain.zig`), soil is 16 interchangeable fill tiles.
pub const map_grass = @embedFile("map/grass.png");
pub const map_soil = @embedFile("map/soil.png");

// The player, a 4-frame loop of 32 x 32 (see `PLAYER_ANIM_FPS`).
pub const player_1 = @embedFile("player/1.png");
pub const player_2 = @embedFile("player/2.png");
pub const player_3 = @embedFile("player/3.png");
pub const player_4 = @embedFile("player/4.png");

// Blocks: four interchangeable faces for regular blocks (32 x 32), the gold
// block (32 x 32) and the 2 x 2 mini boss (64 x 64).
pub const block_face_1 = @embedFile("blocks/Layer 1.png");
pub const block_face_2 = @embedFile("blocks/Enemies 2.png");
pub const block_face_3 = @embedFile("blocks/Enemies 3.png");
pub const block_face_4 = @embedFile("blocks/Enemies4.png");
pub const block_gold = @embedFile("blocks/golden.png");
pub const block_boss = @embedFile("blocks/Boss.png");
