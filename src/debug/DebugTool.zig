const controls_panel = @import("panels/controls.zig");
const inspector_panel = @import("panels/inspector.zig");

// In-game debugging UI: a handful of ImGui panels for inspecting and
// controlling a running Game. main.zig owns one of these and calls
// `render()` once per frame, from inside an rlImGuiBegin/End bracket.
//
// Each panel lives in its own file under `panels/`, one per concern --
// same shape as `game/systems/`. `DebugTool` just owns whatever state a
// panel needs to keep between frames (e.g. pause/step, the selected
// entity) and fans out to each panel's `render()`.

pub const DebugTool = struct {
    controls: controls_panel.State = .{},
    inspector: inspector_panel.State = .{},

    /// Whether main.zig should advance the game this frame. Delegates to
    /// the controls panel: freely running, or paused with a queued step.
    pub fn shouldStep(self: *DebugTool) bool {
        return self.controls.shouldStep();
    }

    /// Renders every panel. `dt` is this frame's raw delta time (shown by
    /// the Inspector regardless of pause state). `Game` is the Game (see
    /// Game.zig) being monitored -- threaded through explicitly, comptime,
    /// since Game is a singleton module rather than a value.
    pub fn render(self: *DebugTool, dt: f32, comptime Game: type) void {
        controls_panel.render(&self.controls);
        if (Game.currentScene()) |scn| {
            inspector_panel.render(&self.inspector, dt, scn);
        }
    }
};
