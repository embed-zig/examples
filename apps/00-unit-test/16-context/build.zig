const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const embed_dep = b.dependency("embed_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const tests_context_mod = b.createModule(.{
        .root_source_file = embed_dep.path("lib/tests/context.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "embed", .module = embed_dep.module("embed") },
            .{ .name = "testing", .module = embed_dep.module("testing") },
            .{ .name = "context", .module = embed_dep.module("context") },
        },
    });
    b.modules.put(b.dupe("tests_context"), tests_context_mod) catch @panic("OOM");

    const app_mod = b.addModule("app", .{
        .root_source_file = b.path("src/app.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "tests_context", .module = tests_context_mod },
            .{ .name = "testing", .module = embed_dep.module("testing") },
        },
    });

    const tests = b.addTest(.{
        .root_module = app_mod,
    });
    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run host tests for unit-test-context");
    test_step.dependOn(&run_tests.step);
    b.default_step = test_step;
}
