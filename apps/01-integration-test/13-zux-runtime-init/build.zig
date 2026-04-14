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
            .{ .name = "zux", .module = embed_dep.module("zux") },
            .{ .name = "embed_std", .module = embed_dep.module("embed_std") },
            .{ .name = "drivers", .module = embed_dep.module("drivers") },
        },
    });

    const tests = b.addTest(.{
        .root_module = app_mod,
    });
    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run host tests for integration-test-zux-runtime-init");
    test_step.dependOn(&run_tests.step);
    b.default_step = test_step;
}
