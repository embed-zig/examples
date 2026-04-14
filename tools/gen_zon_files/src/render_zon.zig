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
    remote_hashes: config.RemoteHashes,
    apps: []const discover_apps.App,
    host_platform: discover_apps.Platform,
) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();

    try renderToWriter(allocator, &out.writer, variant, cfg, remote_hashes, apps, host_platform);
    const bytes = out.writer.buffered();
    return try allocator.dupe(u8, bytes);
}

fn renderToWriter(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    variant: Variant,
    cfg: config.PackageJson,
    remote_hashes: config.RemoteHashes,
    apps: []const discover_apps.App,
    host_platform: discover_apps.Platform,
) !void {
    const spec = specFor(variant);
    const target_platform = switch (variant) {
        .root, .desktop => host_platform,
        .esp => .esp,
    };

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
            const embed_dep_spec = try config.parseDependencySpec(cfg.dependencies.@"embed-zig");
            const embed_url = try config.remoteUrlForDependencySpec(allocator, "embed-zig", embed_dep_spec);
            defer allocator.free(embed_url);
            try deps.field("embed_zig", .{
                .url = embed_url,
                .hash = remote_hashes.embed_zig,
            }, .{});
        }

        for (apps) |app| {
            if (!app.supportsPlatform(target_platform)) continue;

            var path_buf: [256]u8 = undefined;
            const dep_path = switch (variant) {
                .root => app.root_path,
                .esp, .desktop => try std.fmt.bufPrint(&path_buf, "../{s}", .{app.root_path}),
            };
            try deps.field(app.key, .{ .path = dep_path }, .{});
        }

        if (spec.include_esp_dependency) {
            const esp_dep_spec = try config.parseDependencySpec(cfg.dependencies.esp);
            const esp_url = try config.remoteUrlForDependencySpec(allocator, "esp", esp_dep_spec);
            defer allocator.free(esp_url);
            try deps.field("esp", .{
                .url = esp_url,
                .hash = remote_hashes.esp,
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
