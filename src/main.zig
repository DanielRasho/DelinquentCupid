const std = @import("std");
const rl = @import("raylib");
const zgui = @import("zgui");
const c = @cImport({
    @cDefine("NO_FONT_AWESOME", "1");
    @cInclude("rlImGui.h");
});
const ecs = @import("ecs");
const Game = @import("Game.zig");
const DebugTool = @import("debug/DebugTool.zig").DebugTool;
const constants = @import("game/systems/constants.zig");

// ENTITITES
const comps = @import("game/components.zig");

// ENTITITES
const game_system = @import("game/systems/game.zig").game_system;
const paddle_system = @import("game/systems/paddle.zig").paddle_system;
const ball_system = @import("game/systems/ball.zig").ball_system;
const brick_system = @import("game/systems/brick.zig").brick_system;
const render_system = @import("game/systems/render.zig").render_system;

const WINDOW_W: i32 = @intFromFloat(constants.SCREEN_W);
const WINDOW_H: i32 = @intFromFloat(constants.SCREEN_H);

/// The only scene today. Builds and registers the same five systems
/// main.zig used to wire up by hand; Registration order is important and
/// is commented where it used to live: `Game` before `Brick` (brick setup
/// writes the spawned brick count into the singleton's `Score`), and
/// `Paddle` before `Ball` (ball setup reads the paddle's position to snap
/// the ball onto it).
fn gameplayScene(allocator: std.mem.Allocator) !ecs.scene.Scene {
    var scn = try ecs.scene.Scene.init(allocator);
    try scn.register("Game", game_system);
    try scn.register("Paddle", paddle_system);
    try scn.register("Ball", ball_system);
    try scn.register("Brick", brick_system);
    try scn.register("Render", render_system);
    return scn;
}

pub fn main() !void {

    // Initializa allocator
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // =================
    // INITIALIZE
    // =================

    // RAYLIB
    rl.initWindow(WINDOW_W, WINDOW_H, "Zing Zong - Breakout Game");
    defer rl.closeWindow();
    rl.setTargetFPS(60);
    // IMGUI
    c.rlImGuiSetup(true);
    defer c.rlImGuiShutdown();
    zgui.initNoContext(allocator);
    defer zgui.deinitNoContext();

    // Game / Scenes
    Game.init(allocator);
    defer Game.deinit();

    try Game.registerScene("game", gameplayScene);
    try Game.start("game");

    var debug_tool = DebugTool{};

    while (!rl.windowShouldClose()) {
        const dt = rl.getFrameTime();
        // The debug tool's "Pause"/"Next Frame" panel gates whether the
        // game actually advances this frame; rendering below always runs,
        // so the paused game stays visible on screen.
        if (debug_tool.shouldStep()) {
            Game.update(dt);
        }

        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(.dark_gray);

        Game.render();

        // One rlImGuiBegin/End bracket per frame covers every ImGui window
        // -- the HUD and every debug panel -- since rlImGuiBegin starts a
        // new ImGui frame and rlImGuiEnd renders it; nesting a second pair
        // inside the same frame would start ImGui over mid-frame.
        c.rlImGuiBegin();
        debug_tool.render(dt, Game);
        c.rlImGuiEnd();
    }
}
