const std = @import("std");
const rl = @import("raylib");
const zgui = @import("zgui");
const c = @cImport({
    @cDefine("NO_FONT_AWESOME", "1");
    @cInclude("rlImGui.h");
});

const SCREEN_W: i32 = 1024;
const SCREEN_H: i32 = 768;
const PADDLE_SPEED: i32 = 300;

const GameStatus = enum { READY, PLAYING, WIN, LOOSE };

const Paddle = struct {
    rect: rl.Rectangle,
    fn new(width: f32, height: f32) Paddle {
        return Paddle{
            .rect = .{
                .x = @as(f32, @floatFromInt(SCREEN_W)) / 2.0 - width / 2.0,
                .y = SCREEN_H - 40,
                .width = width,
                .height = height,
            },
        };
    }
    fn center(self: Paddle) f32 {
        return self.rect.x + self.rect.width / 2.0;
    }
    fn render(self: *Paddle) void {
        rl.drawRectangleRec(self.rect, .white);
    }
};

const Ball = struct {
    pos: rl.Vector2 = undefined,
    vel: rl.Vector2 = undefined,
    linear_vel: f32 = 350.0,
    radius: f32 = 8.0,

    fn resetBallOnPaddle(self: *Ball, paddle: Paddle) void {
        self.pos = .{ .x = paddle.center(), .y = paddle.rect.y - self.radius - 1.0 };
        self.vel = .{ .x = 0, .y = 0 };
    }

    fn launch(self: *Ball) void {
        const dir = rl.Vector2{ .x = 0.35, .y = -0.9 };
        const len = @sqrt(dir.x * dir.x + dir.y * dir.y);
        self.vel = .{ .x = dir.x / len * self.linear_vel, .y = dir.y / len * self.linear_vel };
    }

    fn updateVel(self: *Ball) void {
        const cur_len = @sqrt(self.vel.x * self.vel.x + self.vel.y * self.vel.y);
        if (cur_len > 0.0001) {
            const scale = self.linear_vel / cur_len;
            self.vel.x *= scale;
            self.vel.y *= scale;
        }
    }

    fn updatePosition(self: *Ball, dt: f32) void {
        self.pos.x += self.vel.x * dt;
        self.pos.y += self.vel.y * dt;
    }

    fn BounceOnField() void {}

    fn bounce() void {}

    fn render(self: *Ball) void {
        rl.drawCircleV(self.pos, self.radius, .white);
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
    fn restartBricks(self: *GameState) void {
        for (self.bricks) |*brick| {
            brick.is_broken = false;
        }
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
    zgui.initNoContext(allocator);
    defer zgui.deinitNoContext();

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

fn update(s: *GameState, dt: f32) void {
    if (s.status == .READY or s.status == .PLAYING) {
        if (rl.isKeyDown(.left) or rl.isKeyDown(.a)) {
            s.paddle.rect.x -= PADDLE_SPEED * dt;
        }
        if (rl.isKeyDown(.right) or rl.isKeyDown(.d)) {
            s.paddle.rect.x += PADDLE_SPEED * dt;
        }
        if (s.paddle.rect.x < 0) s.paddle.rect.x = 0;
        if (s.paddle.rect.x + s.paddle.rect.width > @as(f32, @floatFromInt(SCREEN_W))) {
            s.paddle.rect.x = @as(f32, @floatFromInt(SCREEN_W)) - s.paddle.rect.width;
        }
    }

    switch (s.status) {
        .READY => {
            s.ball.resetBallOnPaddle(s.paddle);
            if (rl.isKeyPressed(.space)) {
                s.ball.launch();
                s.status = .PLAYING;
            }
        },
        .PLAYING => {
            // Modify ball speed
            s.ball.updateVel();
            s.ball.updatePosition(dt);

            // Ball Colisions
            // -- BOTTOM
            if (s.ball.pos.y - s.ball.radius > SCREEN_H) {
                s.lives -= 1;
                if (s.lives <= 0) {
                    s.status = .LOOSE;
                } else {
                    s.ball.resetBallOnPaddle(s.paddle);
                    s.status = .READY;
                }
            }
            // -- OTHER WALLS
            if (s.ball.pos.x - s.ball.radius <= 0) {
                s.ball.pos.x = s.ball.radius;
                s.ball.vel.x = -s.ball.vel.x;
            } else if (s.ball.pos.x + s.ball.radius >= SCREEN_W) {
                s.ball.pos.x = SCREEN_W - s.ball.radius;
                s.ball.vel.x = -s.ball.vel.x;
            }
            if (s.ball.pos.y - s.ball.radius <= 0) {
                s.ball.pos.y = s.ball.radius;
                s.ball.vel.y = -s.ball.vel.y;
            }

            // Paddle collisions
            if (rl.checkCollisionCircleRec(s.ball.pos, s.ball.radius, s.paddle.rect)) {
                if (s.ball.vel.y > 0) {
                    s.ball.pos.y = s.paddle.rect.y - s.ball.radius - 0.5;

                    const hit_post = (s.ball.pos.x - s.paddle.center()) / (s.paddle.rect.width / 2.0);
                    const speed = @sqrt(s.ball.vel.x * s.ball.vel.x + s.ball.vel.y * s.ball.vel.y);

                    // Update velocity
                    s.ball.vel.x = hit_post * speed;
                    s.ball.vel.y = -@abs(s.ball.vel.y);

                    // s.ball.vel.y = -@abs(s.ball.vel.y);
                    // s.ball.vel.y = -@abs(s.ball.vel.y);
                }
            }

            // Brick collisions

            // WIN CHECK
            if (s.broken_bricks == s.bricks.len) {
                s.status = .WIN;
            }
        },
        .WIN => {},
        .LOOSE => {},
    }
}

fn render(s: *GameState) void {
    rl.beginDrawing();
    defer rl.endDrawing();
    rl.clearBackground(.dark_gray);

    // Render Bricks
    for (s.bricks) |brick|
        brick.render();
    // Render Ball
    s.ball.render();
    // Render Paddle
    s.paddle.render();

    // HUD
    c.rlImGuiBegin();
    if (zgui.begin("Game HUD", .{})) {
        zgui.text("Lives: {d}", .{s.lives});
        zgui.text("Bricks left: {d}", .{s.bricks.len - s.broken_bricks});
        zgui.text("Total bricks: {d}", .{s.bricks.len});
        zgui.separator();
        _ = zgui.sliderFloat("Ball speed", .{ .v = &s.ball.linear_vel, .min = 150.0, .max = 800.0 });
        if (zgui.button("Restart", .{})) {
            s.paddle.rect.x = @as(f32, @floatFromInt(SCREEN_W)) / 2.0 - s.paddle.rect.width / 2.0;
            s.restartBricks();
            s.ball.resetBallOnPaddle(s.paddle);
            s.lives = 3;
            s.status = .READY;
        }
    }
    zgui.end();
    c.rlImGuiEnd();
}
