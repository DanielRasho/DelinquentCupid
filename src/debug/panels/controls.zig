const zgui = @import("zgui");
const constants = @import("../../game/systems/constants.zig");

/// Pause / Play / Next Frame. Doesn't touch the game loop itself -- it just
/// tracks whether the loop should be advancing, and lets `main.zig` (which
/// owns the loop) ask via `shouldStep()`.
pub const State = struct {
    paused: bool = false,
    step_once: bool = false,

    /// Whether the caller should advance the game this frame: freely
    /// running, or paused with exactly one step queued up by "Next Frame".
    pub fn shouldStep(self: *State) bool {
        if (!self.paused) return true;
        if (self.step_once) {
            self.step_once = false;
            return true;
        }
        return false;
    }
};

pub fn render(state: *State) void {
    zgui.setNextWindowPos(.{ .x = constants.SCREEN_W / 2.0, .y = 10.0, .pivot_x = 0.5, .cond = .first_use_ever });

    if (zgui.begin("Debug Controls", .{ .flags = .{ .always_auto_resize = true } })) {
        // Snapshot once: a button click below mutates state.paused, and
        // beginDisabled/endDisabled must agree with each other regardless,
        // or ImGui's disabled-stack ends up unbalanced.
        const paused = state.paused;

        if (paused) zgui.beginDisabled(.{});
        if (zgui.button("Pause", .{})) state.paused = true;
        if (paused) zgui.endDisabled();

        zgui.sameLine(.{});
        if (!paused) zgui.beginDisabled(.{});
        if (zgui.button("Play", .{})) state.paused = false;
        if (!paused) zgui.endDisabled();

        zgui.sameLine(.{});
        if (!paused) zgui.beginDisabled(.{});
        if (zgui.button("Next Frame", .{})) state.step_once = true;
        if (!paused) zgui.endDisabled();
    }
    zgui.end();
}
