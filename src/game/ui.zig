//! Immediate-mode drawing helpers shared by every screen and panel. All text
//! goes through here, so this is the one place to swap in a custom font.
const std = @import("std");
const rl = @import("raylib");
const zgui = @import("zgui");

/// Formats into `buf` as a zero-terminated string raylib can draw.
pub fn format(buf: []u8, comptime fmt: []const u8, args: anytype) [:0]const u8 {
    return std.fmt.bufPrintZ(buf, fmt, args) catch "?";
}

pub fn text(str: [:0]const u8, x: f32, y: f32, size: i32, color: rl.Color) void {
    rl.drawText(str, @intFromFloat(x), @intFromFloat(y), size, color);
}

/// Draws `str` horizontally centred on `center_x`, with its top at `y`.
pub fn textCentered(str: [:0]const u8, center_x: f32, y: f32, size: i32, color: rl.Color) void {
    const width: f32 = @floatFromInt(rl.measureText(str, size));
    text(str, center_x - width / 2.0, y, size, color);
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

/// Draws a button; it lights up under the cursor while `enabled`.
pub fn button(rect: rl.Rectangle, label: [:0]const u8, size: i32, enabled: bool) void {
    const hovered = enabled and rl.checkCollisionPointRec(rl.getMousePosition(), rect);
    const fill: rl.Color = if (hovered) .light_gray else if (enabled) .gray else rl.fade(.gray, 0.3);
    const ink: rl.Color = if (enabled) .black else .gray;
    rl.drawRectangleRec(rect, fill);
    rl.drawRectangleLinesEx(rect, 2.0, ink);
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
