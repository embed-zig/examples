const std = @import("std");
const Step = std.Build.Step;
const apps_manifest = @import("build/apps_manifest.zig");
const esp_pipeline = @import("build/esp_pipeline.zig");

const root_manifest_rel_path = "build/root_apps_manifest.json";
const esp_manifest_rel_path = "build/esp_apps_manifest.json";

fn isAppDependencyName(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "unit-test_") or
        std.mem.startsWith(u8, name, "integration-test_");
}

fn countAppDependencies(b: *std.Build) usize {
    var count: usize = 0;
    for (b.available_deps) |dep| {
        if (isAppDependencyName(dep[0])) count += 1;
    }
    return count;
}

pub fn build(b: *std.Build) void {
    const root_manifest_path = b.pathFromRoot(root_manifest_rel_path);
    defer b.allocator.free(root_manifest_path);
    const esp_manifest_path = b.pathFromRoot(esp_manifest_rel_path);
    defer b.allocator.free(esp_manifest_path);

    var manifest = apps_manifest.loadFromAbsolutePath(b.allocator, root_manifest_path) catch |err| switch (err) {
        error.FileNotFound => std.debug.panic(
            "missing committed apps manifest '{s}'",
            .{root_manifest_path},
        ),
        else => std.debug.panic("load committed apps manifest '{s}': {}", .{ root_manifest_path, err }),
    };
    defer manifest.deinit();

    const manifest_apps = manifest.parsed.value.apps;
    if (countAppDependencies(b) != manifest_apps.len) {
        std.debug.panic(
            "committed apps manifest '{s}' does not match root build.zig.zon",
            .{root_manifest_path},
        );
    }

    const root = b.build_root.handle;
    const test_step = b.step("test", "Run zig build test in each package listed in the committed apps manifest");
    for (manifest_apps) |app| {
        const build_file_rel = b.fmt("{s}/build.zig", .{app.root_path});
        root.access(build_file_rel, .{}) catch {
            std.debug.panic(
                "committed apps manifest entry '{s}' points to missing package '{s}'",
                .{ app.key, app.root_path },
            );
        };

        const run = Step.Run.create(b, b.fmt("zig build test ({s})", .{app.root_path}));
        run.addArgs(&.{ "zig", "build", "test" });
        run.setCwd(b.path(app.root_path));
        run.stdio = .inherit;
        test_step.dependOn(&run.step);
    }

    b.default_step = test_step;

    const idf = b.option([]const u8, "idf", "ESP-IDF root directory; passed as IDF_PATH to esp zig build (required for zig build esp)");

    const esp_step = b.step("esp", "Run zig build in esp/ for each app via embed.testing matrix (needs -Didf=...)");
    if (idf) |path| {
        const embed_dep = b.dependency("embed_zig", .{
            .target = b.graph.host,
            .optimize = .Debug,
        });
        esp_pipeline.addCompileMatrixRun(b, esp_step, path, esp_manifest_path, embed_dep);
    } else {
        esp_pipeline.addRequiresIdfStep(b, esp_step);
    }

    const desktop_step = b.step("desktop", "Reserved: desktop compile matrix");
    {
        const run = Step.Run.create(b, "desktop (not implemented)");
        run.addArgs(&.{ "sh", "-c", "echo 'compat-tests: desktop compile matrix is not implemented yet'; exit 0" });
        run.stdio = .inherit;
        desktop_step.dependOn(&run.step);
    }
}
