const std = @import("std");
const config = @import("config.zig");
const discover_apps = @import("discover_apps.zig");

pub const Variant = enum {
    root,
    esp,
    desktop,
};

const PackageName = enum {
    compat_tests,
    esp_example,
    compat_tests_desktop,
};

const VariantSpec = struct {
    name: PackageName,
    fingerprint: u64,
    include_embed_dependency: bool = false,
    include_esp_dependency: bool = false,
    paths: []const []const u8,
};

const root_paths = [_][]const u8{
    "build.zig",
    "build",
};

const desktop_paths = [_][]const u8{
    "build.zig",
    "build",
};

const esp_paths = [_][]const u8{
    "build.zig",
    "build.zig.zon",
    "build",
    "board",
    "c_helper",
    "src",
};

fn specFor(variant: Variant) VariantSpec {
    return switch (variant) {
        .root => .{
            .name = .compat_tests,
            .fingerprint = 0x1e73b30057af9b47,
            .include_embed_dependency = true,
            .paths = &root_paths,
        },
        .esp => .{
            .name = .esp_example,
            .fingerprint = 0xd85fd353434c8afb,
            .include_esp_dependency = true,
            .paths = &esp_paths,
        },
        .desktop => .{
            .name = .compat_tests_desktop,
            .fingerprint = 0x2f84c41168b0ac5e,
            .include_embed_dependency = true,
            .paths = &desktop_paths,
        },
    };
}

pub fn render(
    allocator: std.mem.Allocator,
    variant: Variant,
    cfg: config.PackageJson,
    package_hashes: config.PackageHashes,
    apps: []const discover_apps.App,
) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();

    try renderToWriter(allocator, &out.writer, variant, cfg, package_hashes, apps);
    const bytes = out.writer.buffered();
    return try allocator.dupe(u8, bytes);
}

fn renderToWriter(
    _: std.mem.Allocator,
    writer: *std.Io.Writer,
    variant: Variant,
    cfg: config.PackageJson,
    package_hashes: config.PackageHashes,
    apps: []const discover_apps.App,
) !void {
    const spec = specFor(variant);

    var serializer: std.zon.Serializer = .{
        .writer = writer,
        .options = .{ .whitespace = true },
    };

    var root = try serializer.beginStruct(.{});
    try root.field("name", spec.name, .{});
    try root.field("version", cfg.version, .{});
    try root.field("fingerprint", spec.fingerprint, .{});
    try root.field("minimum_zig_version", cfg.zon.minimum_zig_version, .{});

    {
        var deps = try root.beginStructField("dependencies", .{});

        if (spec.include_embed_dependency) {
            try deps.field("embed_zig", .{
                .url = package_hashes.embed_zig.url,
                .hash = package_hashes.embed_zig.hash,
            }, .{});
        }

        for (apps) |app| {
            const include: bool = switch (variant) {
                .root, .desktop => discover_apps.appSupportsAnyPlatform(app, &discover_apps.desktop_repo_platforms),
                .esp => app.supportsPlatform(.esp),
            };
            if (!include) continue;

            var path_buf: [256]u8 = undefined;
            const dep_path = switch (variant) {
                .root => app.root_path,
                .esp, .desktop => try std.fmt.bufPrint(&path_buf, "../{s}", .{app.root_path}),
            };
            try deps.field(app.key, .{ .path = dep_path }, .{});
        }

        if (spec.include_esp_dependency) {
            try deps.field("esp", .{
                .url = package_hashes.esp.url,
                .hash = package_hashes.esp.hash,
            }, .{});
        }

        try deps.end();
    }

    {
        var paths = try root.beginTupleField("paths", .{});
        for (spec.paths) |path| {
            try paths.field(path, .{});
        }
        try paths.end();
    }

    try root.end();
    try writer.writeByte('\n');
}
