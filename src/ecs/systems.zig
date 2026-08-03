const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const scene = @import("scene.zig");

pub const System = struct {
    enabled: bool = true,

    // ===============
    // CALLBACKS
    // ===============

    setup: *const fn (sys: *System, scn: *scene.Scene) void = &defaultSetup,
    update: *const fn (sys: *System, scn: *scene.Scene, dt: f32) void = &defaultUpdate,
    render: *const fn (sys: *System, scn: *scene.Scene) void = &defaultRender,
    destroy: *const fn (sys: *System, scn: *scene.Scene) void = &defaultDestroy,

    fn defaultSetup(_: *System, _: *scene.Scene) void {}
    fn defaultUpdate(_: *System, _: *scene.Scene, _: f32) void {}
    fn defaultRender(_: *System, _: *scene.Scene) void {}
    fn defaultDestroy(_: *System, _: *scene.Scene) void {}
};
