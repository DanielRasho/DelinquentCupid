//! Easing curves shared by the animations: each maps progress `t` in
//! [0, 1] to [0, 1], with `f(0) = 0` and `f(1) = 1`.
const std = @import("std");

/// Cubic ease-in-out: starts slow, speeds up, slows down into `t` = 1.
pub fn inOutCubic(t: f32) f32 {
    if (t < 0.5) return 4 * t * t * t;
    const u = -2 * t + 2;
    return 1 - u * u * u / 2;
}

test "inOutCubic hits its ends and middle, and is symmetric" {
    const eps = 1e-6;
    try std.testing.expectApproxEqAbs(@as(f32, 0), inOutCubic(0), eps);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), inOutCubic(0.5), eps);
    try std.testing.expectApproxEqAbs(@as(f32, 1), inOutCubic(1), eps);
    try std.testing.expectApproxEqAbs(1 - inOutCubic(0.2), inOutCubic(0.8), eps);
}
