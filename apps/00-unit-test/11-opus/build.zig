const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const embed_dep = b.dependency("embed_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const opus_dep = b.dependency("opus", .{
        .target = target,
        .optimize = optimize,
        .opus_config_header = b.path("opus_config.h"),
    });
    const opus_mod = opus_dep.module("opus");
    opus_mod.addImport("embed", embed_dep.module("embed"));
    opus_mod.addImport("testing", embed_dep.module("testing"));

    const app_mod = b.addModule("app", .{
        .root_source_file = b.path("src/app.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "embed", .module = embed_dep.module("embed") },
            .{ .name = "opus", .module = opus_mod },
            .{ .name = "testing", .module = embed_dep.module("testing") },
        },
    });

    const tests = b.addTest(.{
        .root_module = app_mod,
    });
    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run host tests for unit-test-opus");
    test_step.dependOn(&run_tests.step);
    b.default_step = test_step;
}
