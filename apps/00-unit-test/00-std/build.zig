const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const embed_dep = b.dependency("embed_zig", .{
        .target = target,
        .optimize = optimize,
    });
    b.modules.put(b.dupe("embed"), embed_dep.module("embed")) catch @panic("OOM");
    b.modules.put(b.dupe("embed_std"), embed_dep.module("embed_std")) catch @panic("OOM");
    b.modules.put(b.dupe("context"), embed_dep.module("context")) catch @panic("OOM");
    b.modules.put(b.dupe("sync"), embed_dep.module("sync")) catch @panic("OOM");
    b.modules.put(b.dupe("net"), embed_dep.module("net")) catch @panic("OOM");
    b.modules.put(b.dupe("testing"), embed_dep.module("testing")) catch @panic("OOM");

    const tests_embed_mod = b.createModule(.{
        .root_source_file = embed_dep.path("lib/tests/embed.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "embed", .module = embed_dep.module("embed") },
            .{ .name = "embed_std", .module = embed_dep.module("embed_std") },
            .{ .name = "testing", .module = embed_dep.module("testing") },
        },
    });
    b.modules.put(b.dupe("tests_embed"), tests_embed_mod) catch @panic("OOM");

    const app_mod = b.addModule("app", .{
        .root_source_file = b.path("src/app.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "embed", .module = embed_dep.module("embed") },
            .{ .name = "tests_embed", .module = tests_embed_mod },
            .{ .name = "testing", .module = embed_dep.module("testing") },
        },
    });

    const tests = b.addTest(.{
        .root_module = app_mod,
    });
    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run host tests for unit-test-std");
    test_step.dependOn(&run_tests.step);
    b.default_step = test_step;
}
