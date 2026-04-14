//! Root `build.zig` helpers for the `esp` step (`zig build esp -Didf=…`).

const std = @import("std");
const Build = std.Build;
const Step = Build.Step;

pub fn addRequiresIdfStep(b: *Build, esp_step: *Step) void {
    const run = Step.Run.create(b, "require -Didf for esp");
    run.addArgs(&.{ "sh", "-c", "echo 'compat-tests: zig build esp requires -Didf=/path/to/esp-idf (sets IDF_PATH)' >&2; exit 1" });
    esp_step.dependOn(&run.step);
}

/// Builds and runs `build/esp_compile_matrix.zig`, which uses `embed.testing` with one
/// `TestRunner` per ESP app (`t.run("<app>", …)`). Sets `COMPAT_TESTS_ROOT`, `IDF_PATH`,
/// and `COMPAT_TESTS_MANIFEST`.
pub fn addCompileMatrixRun(
    b: *Build,
    esp_step: *Step,
    idf_path: []const u8,
    manifest_path: []const u8,
    embed_dep: *Build.Dependency,
) void {
    const mod = b.createModule(.{
        .root_source_file = b.path("build/esp_compile_matrix.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
        .imports = &.{
            .{ .name = "embed", .module = embed_dep.module("embed") },
            .{ .name = "embed_std", .module = embed_dep.module("embed_std") },
            .{ .name = "testing", .module = embed_dep.module("testing") },
        },
    });
    const exe = b.addExecutable(.{
        .name = "esp_compile_matrix",
        .root_module = mod,
    });
    const run = b.addRunArtifact(exe);
    run.stdio = .inherit;
    const repo_root = b.pathFromRoot(".");
    defer b.allocator.free(repo_root);
    run.setEnvironmentVariable("COMPAT_TESTS_ROOT", repo_root);
    run.setEnvironmentVariable("IDF_PATH", idf_path);
    run.setEnvironmentVariable("COMPAT_TESTS_MANIFEST", manifest_path);
    esp_step.dependOn(&run.step);
}
