const std = @import("std");
const zgui = @import("zgui");
const ecs = @import("ecs");
const constants = @import("../../game/systems/constants.zig");

const Game = ecs.Game;
const Scene = ecs.scene.Scene;

/// Scene switching is deferred: pressing a scene button only records the
/// request here, and `DebugTool` honors it once every panel has finished
/// drawing for the frame. Switching right away from inside the button would
/// tear down the scene the other panels are still pointing at. Going through
/// a `Game.SwitchRequest` entity instead wouldn't work either: the Game only
/// honors those from `update()`, which the loop controls may have paused.
pub const State = struct {
    pending_switch: ?[]const u8 = null,

    /// The scene requested this frame, if any. Clears the request.
    pub fn takePendingSwitch(self: *State) ?[]const u8 {
        defer self.pending_switch = null;
        return self.pending_switch;
    }
};

pub fn render(state: *State, game: *Game) void {
    zgui.setNextWindowPos(.{ .x = 10.0, .y = constants.SCREEN_H - 10.0, .pivot_y = 1.0, .cond = .first_use_ever });

    if (zgui.begin("Scenes & Systems", .{ .flags = .{} })) {
        renderScenes(state, game);
        if (game.currentScene()) |scn| renderSystems(scn);
    }
    zgui.end();
}

fn renderScenes(state: *State, game: *Game) void {
    if (!zgui.collapsingHeader("Scenes", .{ .default_open = true })) return;

    const names = game.sceneNames(game.allocator) catch |err| {
        std.log.err("scenes panel: failed to list scenes: {}", .{err});
        return;
    };
    defer game.allocator.free(names);

    const current = game.currentName();
    for (names) |name| {
        var buf: [128]u8 = undefined;
        const label = std.fmt.bufPrintZ(&buf, "{s}", .{name}) catch continue;
        // The running scene stays clickable on purpose: switching to it again
        // rebuilds it from its factory, which is how you restart a scene.
        if (zgui.button(label, .{})) state.pending_switch = name;
        if (current != null and std.mem.eql(u8, current.?, name)) {
            zgui.sameLine(.{});
            zgui.textDisabled("(current)", .{});
        }
    }
}

fn renderSystems(scn: *Scene) void {
    if (!zgui.collapsingHeader("Systems", .{ .default_open = true })) return;

    // Only `update` is gated by `enabled` (see ecs/systems.zig), so unticking
    // a system freezes its logic while it keeps drawing and keeps tearing its
    // entities down on scene switch.
    for (scn.systems.keys(), scn.systems.values()) |name, *sys| {
        var buf: [128]u8 = undefined;
        const label = std.fmt.bufPrintZ(&buf, "{s}", .{name}) catch continue;
        _ = zgui.checkbox(label, .{ .v = &sys.enabled });
    }
}
