const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zig_test",
        .use_llvm = true,
        .use_lld = true,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{},
        }),
    });

    // ========================
    // == RAYLIB
    // ========================

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
        .linkage = .dynamic,
    });

    const raylib = raylib_dep.module("raylib"); // main raylib module
    const raygui = raylib_dep.module("raygui"); // raygui module
    const raylib_artifact = raylib_dep.artifact("raylib"); // raylib C library

    exe.root_module.linkLibrary(raylib_artifact);
    exe.root_module.addImport("raylib", raylib);
    exe.root_module.addImport("raygui", raygui);

    // ========================
    // == ZGUI (ImGUI)
    // ========================
    const zgui = b.dependency("zgui", .{
        .shared = false,
        .with_implot = true,
    });
    exe.root_module.addImport("zgui", zgui.module("root"));
    exe.root_module.linkLibrary(zgui.artifact("imgui"));
    exe.root_module.addIncludePath(zgui.path("libs/imgui"));

    // =============
    const rlimgui = b.dependency("rlimgui", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addCSourceFile(.{
        .file = rlimgui.path("rlImGui.cpp"),
        .flags = &.{
            "-fno-sanitize=undefined",
            "-std=c++11",
            "-Wno-deprecated-declarations",
            "-DNO_FONT_AWESOME",
        },
    });
    // exe.addIncludePath(rlimgui.path("."));
    exe.root_module.addIncludePath(rlimgui.path("."));

    // ========================
    // == INSTALL STEP
    // ========================

    b.installArtifact(exe);

    // ========================
    // == RUN STEP
    // ========================
    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // ========================
    // == TESTS
    // ========================

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
