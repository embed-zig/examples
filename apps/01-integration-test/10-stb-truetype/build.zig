const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const embed_dep = b.dependency("embed_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const stb_dep = b.dependency("stb_truetype", .{
        .target = target,
        .optimize = optimize,
    });

    const stb_mod = stb_dep.module("stb_truetype");
    stb_mod.addImport("embed", embed_dep.module("embed"));
    stb_mod.addImport("testing", embed_dep.module("testing"));

    const app_mod = b.addModule("app", .{
        .root_source_file = b.path("src/app.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "stb_truetype", .module = stb_mod },
            .{ .name = "testing", .module = embed_dep.module("testing") },
        },
    });

    const tests = b.addTest(.{ .root_module = app_mod });
    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run host tests for integration-test-stb-truetype");
    test_step.dependOn(&run_tests.step);
    b.default_step = test_step;
}
