const std = @import("std");
const rl = @import("raylib");
const zgui = @import("zgui");
const c = @cImport({
    @cDefine("NO_FONT_AWESOME", "1");
    @cInclude("rlImGui.h");
});

const SCREEN_W: i32 = 1024;
const SCREEN_H: i32 = 768;

const GameStatus = enum { READY, PLAYING, WIN, LOOSE };

const Paddle = struct {
    rect: rl.Rectangle,
    fn new(width: f32, height: f32) Paddle {
        return Paddle{
            .rect = .{
                .x = @as(f32, @floatFromInt(SCREEN_W)) / 2.0 - width / 2.0,
                .y = height,
                .width = width,
                .height = height,
            },
        };
    }
    fn center(self: Paddle) f32 {
        return self.rect.x + self.rect.width / 2.0;
    }
};

const Ball = struct {
    pos: rl.Vector2 = undefined,
    vel: rl.Vector2 = undefined,
    radius: f32 = 8.0,

    fn resetBallOnPaddle(self: *Ball, paddle: Paddle) void {
        self.pos = .{ .x = paddle.center(), .y = paddle.rect.y - self.radius - 1.0 };
        self.vel = .{ .x = 0, .y = 0 };
    }
};

const Brick = struct {
    rect: rl.Rectangle,
    color: rl.Color,
    is_broken: bool = false,
    fn render(self: *const Brick) void {
        if (self.is_broken) return;
        rl.drawRectangleRec(self.rect, self.color);
        rl.drawRectangleLinesEx(self.rect, 1.0, .black);
    }
};

const BrickLayout = struct {
    columns: u8 = 5,
    rows: u8 = 5,
    gap: f32 = 6.0,
    top_offset: f32 = 60.0,
    left_offset: f32 = 12.0,
    brick_width: f32 = 90.0,
    brick_height: f32 = 28.0,

    pub fn createLayout(self: *const BrickLayout, allocator: std.mem.Allocator) ![]Brick {
        const bricks = try allocator.alloc(Brick, self.rows * self.columns);
        const ROW_COLORS = [_]rl.Color{ .red, .orange, .yellow, .green, .sky_blue };
        const TOTAL_WIDTH: f32 = self.columns * self.brick_width +
            if (self.columns > 0) (self.columns - 1) * self.gap else 0;
        const LEFT_OFFSET: f32 = (SCREEN_W - TOTAL_WIDTH) / 2.0;

        for (0..self.rows) |row| {
            for (0..self.columns) |col| {
                const x: f32 = LEFT_OFFSET + @as(f32, @floatFromInt(col)) * (self.brick_width + self.gap);
                const y: f32 = self.top_offset + @as(f32, @floatFromInt(row)) * (self.brick_height + self.gap);
                bricks[row * self.columns + col] = Brick{
                    .rect = .{
                        .x = x,
                        .y = y,
                        .width = self.brick_width,
                        .height = self.brick_height,
                    },
                    .is_broken = false,
                    .color = ROW_COLORS[row % ROW_COLORS.len],
                };
            }
        }

        return bricks;
    }
};

const GameState = struct {
    bricks: []Brick,
    paddle: Paddle,
    ball: Ball,
    broken_bricks: u8 = 0,
    lives: u8 = 3,
    status: GameStatus = .READY,
    fn deinit(self: *GameState, allocator: std.mem.Allocator) !void {
        allocator.free(self.bricks);
    }
};

fn centerScreen() rl.Vector2 {
    return .{ .x = SCREEN_W / 2.0, .y = SCREEN_H / 2.0 };
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
    rl.initWindow(SCREEN_W, SCREEN_H, "Zing Zong - Breakout Game");
    defer rl.closeWindow();
    rl.setTargetFPS(60);
    // IMGUI
    c.rlImGuiSetup(true);
    defer c.rlImGuiShutdown();

    // GAME STATE
    const paddle: Paddle = Paddle.new(120.0, 20.0);
    var ball: Ball = Ball{};
    ball.resetBallOnPaddle(paddle);
    var layout = BrickLayout{};
    var State = GameState{
        .bricks = layout.createLayout(allocator) catch return,
        .paddle = paddle,
        .ball = ball,
        .broken_bricks = 0,
        .lives = 3,
        .status = .READY,
    };
    defer State.deinit(allocator) catch {};

    while (!rl.windowShouldClose()) {
        const dt = rl.getFrameTime();
        update(&State, dt);
        render(&State);
    }
}

fn initialize() void {}

fn update(state: *GameState, _: f32) void {
    switch (state.status) {
        GameStatus.READY, GameStatus.PLAYING => {},
        GameStatus.WIN => {},
        GameStatus.LOOSE => {},
    }
}

fn render(state: *GameState) void {
    rl.beginDrawing();
    defer rl.endDrawing();
    rl.clearBackground(.dark_gray);

    // Draw Bricks
    for (state.bricks) |brick| {
        brick.render();
    }
}
