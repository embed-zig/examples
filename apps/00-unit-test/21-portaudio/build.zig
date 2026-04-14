const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const os_tag = target.result.os.tag;
    const supports_portaudio = os_tag == .macos or os_tag == .linux;
    const embed_dep = b.dependency("embed_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const portaudio_dep = if (supports_portaudio)
        b.dependency("portaudio", .{
            .target = target,
            .optimize = optimize,
        })
    else
        null;

    const app_mod = b.addModule("app", .{
        .root_source_file = if (supports_portaudio)
            b.path("src/app.zig")
        else
            b.path("src/app_unsupported.zig"),
        .target = target,
        .optimize = optimize,
        .imports = if (supports_portaudio)
            &.{
                .{ .name = "portaudio", .module = portaudio_dep.?.module("portaudio") },
                .{ .name = "testing", .module = portaudio_dep.?.module("testing") },
            }
        else
            &.{
                .{ .name = "testing", .module = embed_dep.module("testing") },
            },
    });

    const tests = b.addTest(.{ .root_module = app_mod });
    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run host tests for unit-test-portaudio");
    test_step.dependOn(&run_tests.step);
    b.default_step = test_step;
}
