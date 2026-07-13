const std = @import("std");
const rl = @import("raylib");
const zgui = @import("zgui");

const c = @cImport({
    @cDefine("NO_FONT_AWESOME", "1");
    @cInclude("rlImGui.h");
});

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    rl.initWindow(1024, 768, "raylib + rlImGui + zgui debug window");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    zgui.init(allocator);
    defer zgui.deinit();
    c.rlImGuiSetup(true); // must come after zgui.init

    // --- widget state ---
    var slider_value: f32 = 0.5;
    var name_buf: [128:0]u8 = std.mem.zeroes([128:0]u8);
    @memcpy(name_buf[0..5], "Guest");

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.sky_blue);

        // --- ImGui frame ---
        c.rlImGuiBegin();

        if (zgui.begin("Debug Panel", .{})) {
            zgui.text("Status label: everything nominal", .{});

            if (zgui.sliderFloat("Value", .{ .v = &slider_value, .min = 0.0, .max = 1.0 })) {
                std.debug.print("slider changed: {d:.3}\n", .{slider_value});
            }

            if (zgui.inputText("Name", .{ .buf = name_buf[0..] })) {
                const name = std.mem.sliceTo(&name_buf, 0);
                std.debug.print("name input changed: \"{s}\"\n", .{name});
            }

            if (zgui.button("Log something", .{})) {
                const name = std.mem.sliceTo(&name_buf, 0);
                std.debug.print("button pressed! name=\"{s}\" value={d:.3}\n", .{ name, slider_value });
            }
        }
        zgui.end();

        c.rlImGuiEnd();
    }

    c.rlImGuiShutdown();
}
