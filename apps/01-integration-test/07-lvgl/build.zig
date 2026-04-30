const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const embed_dep = b.dependency("embed_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const app_mod = b.addModule("app", .{
        .root_source_file = b.path("src/app.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "glib", .module = embed_dep.module("glib") },
            .{ .name = "embed", .module = embed_dep.module("embed") },
            .{ .name = "gstd", .module = embed_dep.module("gstd") },
            .{ .name = "lvgl", .module = embed_dep.module("lvgl") },
            .{ .name = "lvgl_osal", .module = embed_dep.module("lvgl_osal") },
        },
    });

    const tests = b.addTest(.{ .root_module = app_mod });
    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run host tests for integration-test-lvgl");
    test_step.dependOn(&run_tests.step);
    b.default_step = test_step;
}
