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
