//! Every texture the game draws. The PNGs are embedded at build time (the
//! `sprite_files` module, `assets/sprites/files.zig`) so the game doesn't
//! depend on the working directory; `load()` decodes them and uploads them to
//! the GPU once, for the whole run.
const std = @import("std");
const rl = @import("raylib");
const files = @import("sprite_files");
const constants = @import("constants.zig");

/// One per embedded PNG. Each name must match a declaration of
/// `assets/sprites/files.zig` (a typo is a compile error in `load`).
pub const Sprite = enum {
    mika_neutral,
    mika_scared,
    mika_happy,
    mika_super_happy,
    mika_ecstatic,
    cupid_chill,
    cupid_motivated,
    cupid_fired_up,
    map_grass,
    map_soil,
    player_1,
    player_2,
    player_3,
    player_4,
    block_face_1,
    block_face_2,
    block_face_3,
    block_face_4,
    block_gold,
    block_boss,
};

/// A looping animation: `frames` shown in order, `fps` of them per second.
pub const Animation = struct {
    frames: []const Sprite,
    fps: f32,

    /// The frame on screen `time` seconds into the animation.
    pub fn frameAt(self: Animation, time: f32) Sprite {
        const count: f32 = @floatFromInt(self.frames.len);
        const index: usize = @intFromFloat(@mod(@floor(time * self.fps), count));
        return self.frames[index];
    }
};

var textures = std.EnumArray(Sprite, ?rl.Texture2D).initFill(null);

/// Needs a window (GPU context), so call it after `rl.initWindow`.
pub fn load() !void {
    errdefer unload();
    inline for (@typeInfo(Sprite).@"enum".fields) |field| {
        const image = try rl.loadImageFromMemory(".png", @field(files, field.name));
        defer rl.unloadImage(image);
        textures.set(@enumFromInt(field.value), try rl.loadTextureFromImage(image));
    }
}

pub fn unload() void {
    for (&textures.values) |*slot| {
        if (slot.*) |texture| rl.unloadTexture(texture);
        slot.* = null;
    }
}

/// Draws tile (`col`, `row`) of `sheet` -- a sheet cut into squares of
/// `TILE_ART_SIZE` -- at `PIXEL_SCALE`, with its top-left corner at (`x`, `y`).
pub fn drawTile(sheet: Sprite, col: u8, row: u8, x: f32, y: f32) void {
    const texture = textures.get(sheet) orelse return;
    const art = constants.TILE_ART_SIZE;
    rl.drawTexturePro(
        texture,
        .{ .x = @as(f32, @floatFromInt(col)) * art, .y = @as(f32, @floatFromInt(row)) * art, .width = art, .height = art },
        .{ .x = @round(x), .y = @round(y), .width = constants.TILE_SIZE, .height = constants.TILE_SIZE },
        .{ .x = 0, .y = 0 },
        0,
        .white,
    );
}

/// Draws `sprite` at `PIXEL_SCALE`, centred in `rect`. It's never stretched
/// to fill `rect`: pixel art only stays crisp at a whole-number scale.
pub fn drawCentered(sprite: Sprite, rect: rl.Rectangle) void {
    const texture = textures.get(sprite) orelse return;
    const art_w: f32 = @floatFromInt(texture.width);
    const art_h: f32 = @floatFromInt(texture.height);
    const w = art_w * constants.PIXEL_SCALE;
    const h = art_h * constants.PIXEL_SCALE;
    rl.drawTexturePro(
        texture,
        .{ .x = 0, .y = 0, .width = art_w, .height = art_h },
        // Whole screen pixels, so every art pixel covers the same area.
        .{ .x = @round(rect.x + (rect.width - w) / 2.0), .y = @round(rect.y + (rect.height - h) / 2.0), .width = w, .height = h },
        .{ .x = 0, .y = 0 },
        0,
        .white,
    );
}

test "an animation advances one frame every 1/fps seconds and loops" {
    const anim = Animation{ .frames = &.{ .player_1, .player_2, .player_3 }, .fps = 4 };
    try std.testing.expectEqual(Sprite.player_1, anim.frameAt(0));
    try std.testing.expectEqual(Sprite.player_1, anim.frameAt(0.24));
    try std.testing.expectEqual(Sprite.player_2, anim.frameAt(0.25));
    try std.testing.expectEqual(Sprite.player_3, anim.frameAt(0.6));
    try std.testing.expectEqual(Sprite.player_1, anim.frameAt(0.75));
    try std.testing.expectEqual(Sprite.player_2, anim.frameAt(100.05));
}
