const rl = @import("raylib");

pub const Position = struct { x: f32, y: f32 };
pub const Velocity = struct { x: f32, y: f32 };
pub const Rectangle = struct { width: f32, height: f32 };
pub const Circle = struct { radius: f32 };
pub const Color = struct { color: rl.Color };

// Tags
pub const Paddle = struct {};
pub const Brick = struct {};

pub const Ball = struct { speed: f32 };

// Singleton components, all set on a single "game" entity.
pub const Status = enum { READY, PLAYING, WIN, LOOSE };
pub const GameStatus = struct { status: Status };
pub const Lives = struct { count: u8 };
pub const Score = struct { broken: u32, total: u32 };
