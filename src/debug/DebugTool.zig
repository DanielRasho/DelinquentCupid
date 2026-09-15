const controls_panel = @import("panels/loop_controls.zig");
const inspector_panel = @import("panels/inspector.zig");
const Game = @import("ecs").Game;

/// Debug tools to interact with the entities, scenes and components of a game.
pub const DebugTool = struct {
    controls: controls_panel.State = .{},
    inspector: inspector_panel.State = .{},

    /// Whether Game should advance the game this frame.
    pub fn shouldStep(self: *DebugTool) bool {
        return self.controls.shouldStep();
    }

    // Renders the debug tools panels.
    pub fn render(self: *DebugTool, dt: f32, game: *Game) void {
        controls_panel.render(&self.controls);
        if (game.currentScene()) |scn| {
            inspector_panel.render(&self.inspector, dt, scn);
        }
    }
};
