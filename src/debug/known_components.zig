const game_components = @import("../game/components.zig");

// The Inspector's editable-component manifest: every component type it
// knows how to render as editable widgets, listed by hand from wherever
// each one actually lives -- a component doesn't need to be declared in
// game/components.zig, or in any particular file, to be part of the game;
// it only needs a line here to become *editable* in the debug tool. See
// panels/inspector.zig's doc comment on `known_components` for why this
// has to be an explicit list rather than something the ECS grows on its
// own as setComponent() gets called.
//
// A component missing from this list still shows up by name wherever the
// Inspector lists an entity's components (that part reads live off the
// ECS, no manifest involved) -- it just can't be expanded into fields.
//
// Import whatever files declare components and list their types here,
// e.g. once components stop being just game/components.zig:
//   const powerups = @import("../game/powerups.zig");
//   ... powerups.Shield, powerups.SpeedBoost, ...
pub const all = .{
    game_components.Ball,
    game_components.Brick,
    game_components.Circle,
    game_components.Color,
    game_components.GameStatus,
    game_components.Lives,
    game_components.Paddle,
    game_components.Position,
    game_components.Rectangle,
    game_components.Score,
    game_components.Velocity,
};
