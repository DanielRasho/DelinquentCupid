const std = @import("std");
const rl = @import("raylib");
const zgui = @import("zgui");
const c = @cImport({
    @cDefine("NO_FONT_AWESOME", "1");
    @cInclude("rlImGui.h");
});
const ecs = @import("ecs");
const Game = ecs.Game;
const DebugTool = @import("debug/DebugTool.zig").DebugTool;
const constants = @import("game/constants.zig");

// SYSTEMS
const game_system = @import("game/systems/game.zig").game_system;
const player_system = @import("game/systems/player.zig").player_system;
const aim_system = @import("game/systems/aim.zig").aim_system;
const shop_system = @import("game/systems/shop.zig").shop_system;
const ball_system = @import("game/systems/ball.zig").ball_system;
const block_system = @import("game/systems/block.zig").block_system;
const render_system = @import("game/systems/render.zig").render_system;
const hud_system = @import("game/systems/hud.zig").hud_system;
const lose_system = @import("game/systems/end_screen.zig").lose_system;

const WINDOW_W: i32 = @intFromFloat(constants.SCREEN_W);
const WINDOW_H: i32 = @intFromFloat(constants.SCREEN_H);

fn gameplayScene(allocator: std.mem.Allocator) !ecs.scene.Scene {
    var scn = try ecs.scene.Scene.init(allocator);
    // `Game` goes first: it spawns the singleton every other system reads.
    // Render callbacks draw in registration order, so `Render` (the field
    // and what's on it) sits before the systems that draw on top of it.
    try scn.register("Game", game_system);
    try scn.register("Player", player_system);
    try scn.register("Render", render_system);
    try scn.register("Aim", aim_system);
    try scn.register("Shop", shop_system);
    try scn.register("Ball", ball_system);
    try scn.register("Block", block_system);
    try scn.register("Hud", hud_system);
    return scn;
}

fn loseScene(allocator: std.mem.Allocator) !ecs.scene.Scene {
    var scn = try ecs.scene.Scene.init(allocator);
    try scn.register("LoseScreen", lose_system);
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
    const game = &Game.instance;
    game.init(allocator);
    defer game.deinit();

    try game.registerScene(constants.SCENE_GAME, gameplayScene);
    try game.registerScene(constants.SCENE_LOSE, loseScene);
    try game.start(constants.SCENE_GAME);

    var debug_tool = DebugTool{};

    while (!rl.windowShouldClose()) {
        const dt = rl.getFrameTime();
        if (debug_tool.shouldStep()) {
            game.update(dt);
        }

        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(.dark_gray);

        game.render();

        // Debug tools SHOULD be run after the frame completion,
        // and within a ImGui render cycle.
        c.rlImGuiBegin();
        debug_tool.render(dt, game);
        c.rlImGuiEnd();
    }
}
