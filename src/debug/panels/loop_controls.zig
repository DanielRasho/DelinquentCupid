const zgui = @import("zgui");
const constants = @import("../../game/constants.zig");

/// State to track how the game should advance on the loop: `play` / `pause` / `one cycle`
pub const State = struct {
    paused: bool = false,
    step_once: bool = false,

    /// Whether the game loop should run freely, or just one cycle.
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
    zgui.setNextWindowPos(.{ .x = constants.SCREEN_W - 10.0, .y = 10.0, .pivot_x = 1.0, .cond = .first_use_ever });

    if (zgui.begin("Debug Controls", .{ .flags = .{ .always_auto_resize = true } })) {
        // Once one of the button has been pressed compute the visual states of
        // the rest of them.
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
