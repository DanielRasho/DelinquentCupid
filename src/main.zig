const std = @import("std");
const rl = @import("raylib");
const zgui = @import("zgui");
const c = @cImport({
    @cDefine("NO_FONT_AWESOME", "1");
    @cInclude("rlImGui.h");
});
const ecs = @import("ecs");
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

    // Scene
    var scene = try ecs.scene.Scene.init(allocator);
    defer scene.deinit();

    // Registration order is important in order to handle the setup correctly
    try scene.register("Game", game_system);
    try scene.register("Paddle", paddle_system);
    try scene.register("Ball", ball_system);
    try scene.register("Brick", brick_system);
    try scene.register("Render", render_system);

    scene.setup();

    while (!rl.windowShouldClose()) {
        const dt = rl.getFrameTime();
        scene.update(dt);

        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(.dark_gray);

        scene.render();
        renderHud(&scene);
    }
    scene.destroy();
}

fn renderHud(scene: *ecs.scene.Scene) void {
    var game_it = scene.entities.query(.{comps.GameStatus});
    const game_id = game_it.next().?;
    const lives = scene.entities.getComponent(game_id, comps.Lives).?;
    const score = scene.entities.getComponent(game_id, comps.Score).?;

    var ball_it = scene.entities.query(.{comps.Ball});
    const ball = scene.entities.getComponent(ball_it.next().?, comps.Ball).?;

    c.rlImGuiBegin();
    if (zgui.begin("Game HUD", .{})) {
        zgui.text("Lives: {d}", .{lives.count});
        zgui.text("Bricks left: {d}", .{score.total - score.broken});
        zgui.text("Total bricks: {d}", .{score.total});
        zgui.separator();
        _ = zgui.sliderFloat("Ball speed", .{ .v = &ball.speed, .min = 150.0, .max = 800.0 });
        if (zgui.button("Restart", .{})) {
            scene.destroy();
            scene.setup();
        }
    }
    zgui.end();
    c.rlImGuiEnd();
}
