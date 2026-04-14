const builtin = @import("builtin");
const std = @import("std");

pub const AppGroup = enum {
    unit,
    integration,

    pub fn keyPrefix(self: AppGroup) []const u8 {
        return switch (self) {
            .unit => "unit-test",
            .integration => "integration-test",
        };
    }

    pub fn manifestName(self: AppGroup) []const u8 {
        return switch (self) {
            .unit => "unit",
            .integration => "integration",
        };
    }
};

pub const Platform = enum {
    esp,
    macos,
    linux,
    windows,
};

const all_platform_names = [_][]const u8{
    "esp",
    "macos",
    "linux",
    "windows",
};

pub const App = struct {
    key: []const u8,
    group: AppGroup,
    root_path: []const u8,
    platforms: std.EnumSet(Platform),

    pub fn supportsPlatform(self: App, platform: Platform) bool {
        return self.platforms.contains(platform);
    }
};

const AppMetadata = struct {
    platforms: []const []const u8 = all_platform_names[0..],
};

const GroupSpec = struct {
    dir_name: []const u8,
    group: AppGroup,
};

const group_specs = [_]GroupSpec{
    .{ .dir_name = "00-unit-test", .group = .unit },
    .{ .dir_name = "01-integration-test", .group = .integration },
};

pub fn suffixAfterNumberDash(name: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < name.len and std.ascii.isDigit(name[i])) : (i += 1) {}
    if (i == 0 or i >= name.len or name[i] != '-') return null;
    return name[i + 1 ..];
}

/// Host desktop OS for logging. Generation of committed root/desktop artifacts uses
/// `desktop_repo_platforms` so output matches across macOS, Linux, and Windows CI.
pub fn hostDesktopPlatform() Platform {
    return switch (builtin.os.tag) {
        .macos => .macos,
        .linux => .linux,
        .windows => .windows,
        else => .linux,
    };
}

pub const desktop_repo_platforms = [_]Platform{ .macos, .linux, .windows };

pub fn appSupportsAnyPlatform(app: App, platforms: []const Platform) bool {
    for (platforms) |p| {
        if (app.supportsPlatform(p)) return true;
    }
    return false;
}

pub fn scan(allocator: std.mem.Allocator, repo_dir: std.fs.Dir) ![]App {
    var apps_dir = try repo_dir.openDir("apps", .{ .iterate = true });
    defer apps_dir.close();

    var apps = std.ArrayListUnmanaged(App){};
    errdefer {
        for (apps.items) |app| {
            allocator.free(app.key);
            allocator.free(app.root_path);
        }
        apps.deinit(allocator);
    }

    for (group_specs) |group_spec| {
        var group_dir = apps_dir.openDir(group_spec.dir_name, .{ .iterate = true }) catch continue;
        defer group_dir.close();

        var child_names = std.ArrayListUnmanaged([]const u8){};
        defer {
            for (child_names.items) |child_name| allocator.free(child_name);
            child_names.deinit(allocator);
        }

        var it = group_dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind != .directory) continue;

            var child_dir = group_dir.openDir(entry.name, .{}) catch continue;
            defer child_dir.close();
            child_dir.access("build.zig", .{}) catch continue;

            try child_names.append(allocator, try allocator.dupe(u8, entry.name));
        }

        std.mem.sort([]const u8, child_names.items, {}, struct {
            fn lt(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.order(u8, a, b) == .lt;
            }
        }.lt);

        for (child_names.items) |child_name| {
            var child_dir = try group_dir.openDir(child_name, .{});
            defer child_dir.close();

            const app_suffix = suffixAfterNumberDash(child_name) orelse continue;
            const key = try std.fmt.allocPrint(allocator, "{s}_{s}", .{
                group_spec.group.keyPrefix(),
                app_suffix,
            });
            errdefer allocator.free(key);

            const root_path = try std.fmt.allocPrint(allocator, "apps/{s}/{s}", .{
                group_spec.dir_name,
                child_name,
            });
            errdefer allocator.free(root_path);

            const platforms = try loadPlatforms(allocator, child_dir);

            try apps.append(allocator, .{
                .key = key,
                .group = group_spec.group,
                .root_path = root_path,
                .platforms = platforms,
            });
        }
    }

    return apps.toOwnedSlice(allocator);
}

pub fn deinitApps(allocator: std.mem.Allocator, apps: []App) void {
    for (apps) |app| {
        allocator.free(app.key);
        allocator.free(app.root_path);
    }
    allocator.free(apps);
}

fn loadPlatforms(allocator: std.mem.Allocator, app_dir: std.fs.Dir) !std.EnumSet(Platform) {
    var file = try app_dir.openFile("build.zig.zon", .{});
    defer file.close();

    const bytes = try file.readToEndAlloc(allocator, 128 * 1024);
    defer allocator.free(bytes);

    const source = try allocator.dupeZ(u8, bytes);
    defer allocator.free(source);

    const metadata = try std.zon.parse.fromSlice(AppMetadata, allocator, source, null, .{
        .ignore_unknown_fields = true,
    });
    defer if (metadata.platforms.ptr != all_platform_names[0..].ptr) {
        for (metadata.platforms) |platform_name| allocator.free(platform_name);
        allocator.free(metadata.platforms);
    };

    var platforms = std.EnumSet(Platform).initEmpty();
    for (metadata.platforms) |platform_name| {
        platforms.insert(try parsePlatform(platform_name));
    }
    return platforms;
}

fn parsePlatform(name: []const u8) !Platform {
    return std.meta.stringToEnum(Platform, name) orelse error.UnknownPlatform;
}
