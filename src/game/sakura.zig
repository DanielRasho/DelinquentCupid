//! The HUD's sakura palette. HUD widgets draw with these rather than
//! raylib's named colours, so the theme stays in one place.
const rl = @import("raylib");

/// The side columns' backdrop, a gradient from `night` (top) to `dusk`.
pub const night = rl.Color.init(52, 26, 48, 255);
pub const dusk = rl.Color.init(104, 48, 82, 255);
/// Classic sakura pink: button faces, borders.
pub const blossom = rl.Color.init(255, 183, 197, 255);
pub const blossom_light = rl.Color.init(255, 221, 228, 255);
/// Deeper rose: button outlines, the combo pill, the spirit meter.
pub const blossom_deep = rl.Color.init(232, 106, 146, 255);
pub const petal_white = rl.Color.init(255, 242, 246, 255);
/// Dark text on pink.
pub const ink = rl.Color.init(74, 28, 52, 255);
