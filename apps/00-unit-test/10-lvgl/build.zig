const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const embed_dep = b.dependency("embed_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const lvgl_dep = b.dependency("lvgl", .{
        .target = target,
        .optimize = optimize,
        .lvgl_config_header = b.path("src/lv_conf.h"),
    });
    const lvgl_mod = lvgl_dep.module("lvgl");
    lvgl_mod.addImport("embed", embed_dep.module("embed"));
    lvgl_mod.addImport("testing", embed_dep.module("testing"));
    lvgl_mod.addImport("drivers", embed_dep.module("drivers"));

    const app_mod = b.addModule("app", .{
        .root_source_file = b.path("src/app.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "embed", .module = embed_dep.module("embed") },
            .{ .name = "lvgl", .module = lvgl_mod },
            .{ .name = "lvgl_osal", .module = lvgl_dep.module("lvgl_osal") },
            .{ .name = "testing", .module = embed_dep.module("testing") },
            .{ .name = "embed_std", .module = embed_dep.module("embed_std") },
            .{ .name = "drivers", .module = embed_dep.module("drivers") },
        },
    });

    const tests = b.addTest(.{
        .root_module = app_mod,
    });
    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run host tests for unit-test-lvgl");
    test_step.dependOn(&run_tests.step);
    b.default_step = test_step;
}
