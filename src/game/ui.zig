//! Immediate-mode drawing helpers shared by every screen and panel. All text
//! goes through here, so this is the one place to swap in a custom font.
const std = @import("std");
const rl = @import("raylib");
const zgui = @import("zgui");
const sakura = @import("sakura.zig");

/// Fredoka, embedded at build time (see the `ui_font` import in build.zig).
const FONT_DATA = @embedFile("ui_font");
/// Glyphs are rasterised once at this size (the biggest text on screen) and
/// scaled down with trilinear filtering, so every size stays smooth.
const FONT_BASE_SIZE: i32 = 96;
/// Extra space between glyphs; 0 keeps the font's own spacing.
const FONT_SPACING: f32 = 0;

var font: ?rl.Font = null;

/// Loads the UI font. Needs a window (GPU context), so call it after
/// `rl.initWindow`; until then text falls back to raylib's default font.
pub fn loadFont() !void {
    var f = try rl.loadFontFromMemory(".ttf", FONT_DATA, FONT_BASE_SIZE, null);
    rl.genTextureMipmaps(&f.texture);
    rl.setTextureFilter(f.texture, .trilinear);
    font = f;
}

pub fn unloadFont() void {
    if (font) |f| rl.unloadFont(f);
    font = null;
}

fn currentFont() rl.Font {
    return font orelse rl.getFontDefault() catch unreachable;
}

/// Formats into `buf` as a zero-terminated string raylib can draw.
pub fn format(buf: []u8, comptime fmt: []const u8, args: anytype) [:0]const u8 {
    return std.fmt.bufPrintZ(buf, fmt, args) catch "?";
}

/// Width in pixels of `str` drawn at `size`.
pub fn measure(str: [:0]const u8, size: i32) f32 {
    return rl.measureTextEx(currentFont(), str, @floatFromInt(size), FONT_SPACING).x;
}

pub fn text(str: [:0]const u8, x: f32, y: f32, size: i32, color: rl.Color) void {
    // Whole pixels keep the glyphs crisp.
    const pos = rl.Vector2{ .x = @round(x), .y = @round(y) };
    rl.drawTextEx(currentFont(), str, pos, @floatFromInt(size), FONT_SPACING, color);
}

/// Draws `str` horizontally centred on `center_x`, with its top at `y`.
pub fn textCentered(str: [:0]const u8, center_x: f32, y: f32, size: i32, color: rl.Color) void {
    text(str, center_x - measure(str, size) / 2.0, y, size, color);
}

/// Draws `str` centred both ways inside `rect`.
pub fn textInRect(str: [:0]const u8, rect: rl.Rectangle, size: i32, color: rl.Color) void {
    const top = rect.y + (rect.height - @as(f32, @floatFromInt(size))) / 2.0;
    textCentered(str, rect.x + rect.width / 2.0, top, size, color);
}

/// A labelled box standing in for art that doesn't exist yet.
pub fn placeholder(rect: rl.Rectangle, label: [:0]const u8, fill: rl.Color) void {
    rl.drawRectangleRec(rect, fill);
    rl.drawRectangleLinesEx(rect, 2.0, .black);
    textInRect(label, rect, 20, .black);
}

/// Corner rounding of `panel`s and buttons (0-1 of their shorter side).
const ROUNDNESS: f32 = 0.4;
const ROUND_SEGMENTS: i32 = 8;

/// A rounded box behind HUD widgets, with a 2 px `edge`.
pub fn panel(rect: rl.Rectangle, fill: rl.Color, edge: rl.Color) void {
    rl.drawRectangleRounded(rect, ROUNDNESS, ROUND_SEGMENTS, fill);
    rl.drawRectangleRoundedLinesEx(rect, ROUNDNESS, ROUND_SEGMENTS, 2.0, edge);
}

/// Draws a sakura-pink button; it lights up under the cursor while
/// `enabled`, and fades into the backdrop while it isn't.
pub fn button(rect: rl.Rectangle, label: [:0]const u8, size: i32, enabled: bool) void {
    const hovered = enabled and rl.checkCollisionPointRec(rl.getMousePosition(), rect);
    const fill: rl.Color = if (hovered) sakura.blossom_light else if (enabled) sakura.blossom else rl.fade(sakura.night, 0.7);
    const edge: rl.Color = if (hovered) sakura.petal_white else if (enabled) sakura.blossom_deep else rl.fade(sakura.blossom, 0.35);
    const ink: rl.Color = if (enabled) sakura.ink else rl.fade(sakura.blossom, 0.5);
    panel(rect, fill, edge);
    // A soft shine across the top half of a live button.
    if (enabled) {
        const shine = rl.Rectangle{ .x = rect.x + 6, .y = rect.y + 4, .width = rect.width - 12, .height = rect.height * 0.4 };
        rl.drawRectangleRounded(shine, 1.0, ROUND_SEGMENTS, rl.fade(sakura.petal_white, 0.35));
    }
    textInRect(label, rect, size, ink);
}

/// A left click this frame that the debug panels didn't take.
pub fn clicked() bool {
    return rl.isMouseButtonPressed(.left) and !zgui.io.getWantCaptureMouse();
}

pub fn clickedIn(rect: rl.Rectangle) bool {
    return clicked() and rl.checkCollisionPointRec(rl.getMousePosition(), rect);
}

/// On/off square wave for "press a key" prompts.
pub fn blink() bool {
    return @mod(rl.getTime(), 1.0) < 0.6;
}
