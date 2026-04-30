const std = @import("std");

const Module = std.Build.Module;

pub const default_build_config_path = "board/esp32s3_devkit/build_config.zig";
/// Default `-Dapp` and `esp/build.zig.zon` dependency key (same string).
///
/// Each app package's own `build.zig.zon` `.name` must be a bare Zig identifier, so it uses the same
/// logical id with `-` mapped to `_` (for example key `integration-test_stb-truetype` → `.name = .integration_test_stb_truetype`).
pub const default_app_name = "unit-test_std";

fn isAppDependencyName(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "unit-test_") or
        std.mem.startsWith(u8, name, "integration-test_");
}

fn collectAppDependencyNames(b: *std.Build) ![][]const u8 {
    var names = std.ArrayList([]const u8).empty;
    errdefer names.deinit(b.allocator);

    // `esp/build.zig.zon` is the source of truth for which app packages are available here.
    for (b.available_deps) |dep| {
        const name = dep[0];
        if (!isAppDependencyName(name)) continue;
        try names.append(b.allocator, name);
    }

    std.mem.sort([]const u8, names.items, {}, struct {
        fn lt(_: void, a: []const u8, b_name: []const u8) bool {
            return std.mem.order(u8, a, b_name) == .lt;
        }
    }.lt);

    return names.toOwnedSlice(b.allocator);
}

pub fn resolveAppName(b: *std.Build) []const u8 {
    const names = collectAppDependencyNames(b) catch |err| {
        std.debug.panic("collect app dependency names: {}", .{err});
    };
    defer {
        b.allocator.free(names);
    }

    if (names.len == 0) {
        std.debug.panic(
            "no app dependencies found in esp/build.zig.zon",
            .{},
        );
    }

    for (names) |name| {
        if (b.option(bool, name, b.fmt("Build the app package {s}", .{name})) orelse false) {
            return b.dupe(name);
        }
    }

    const chosen = b.option([]const u8, "app", "app package name") orelse default_app_name;
    for (names) |name| {
        if (std.mem.eql(u8, chosen, name)) return b.dupe(name);
    }

    std.debug.panic("unknown app '{s}'", .{chosen});
}

pub fn createBuildConfigModule(b: *std.Build) *Module {
    return createBuildConfigModuleAtPath(
        b,
        resolveBuildConfigPath(b),
        b.dependency("esp", .{}).module("esp_idf"),
    );
}

pub fn resolveBuildConfigPath(b: *std.Build) []const u8 {
    return b.option([]const u8, "build_config", "ESP build_config file path") orelse
        default_build_config_path;
}

pub fn createBuildConfigModuleWithIdf(b: *std.Build, esp_idf_module: *Module) *Module {
    return createBuildConfigModuleAtPath(b, resolveBuildConfigPath(b), esp_idf_module);
}

pub fn createBuildConfigModuleAtPath(
    b: *std.Build,
    build_config_path: []const u8,
    esp_idf_module: *Module,
) *Module {
    return b.createModule(.{
        .root_source_file = b.path(build_config_path),
        .imports = &.{
            .{ .name = "esp_idf", .module = esp_idf_module },
        },
    });
}
