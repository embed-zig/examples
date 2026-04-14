const std = @import("std");
const discover_apps = @import("discover_apps.zig");

pub fn render(
    allocator: std.mem.Allocator,
    apps: []const discover_apps.App,
    platform: discover_apps.Platform,
) ![]u8 {
    return renderSupportingAny(allocator, apps, &.{platform});
}

/// Include an app if it supports at least one of `platforms` (e.g. macos, linux, windows for stable CI).
pub fn renderSupportingAny(
    allocator: std.mem.Allocator,
    apps: []const discover_apps.App,
    platforms: []const discover_apps.Platform,
) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();

    try out.writer.writeAll("{\n  \"apps\": [");
    var emitted: usize = 0;
    for (apps, 0..) |app, idx| {
        _ = idx;
        if (!discover_apps.appSupportsAnyPlatform(app, platforms)) continue;

        if (emitted == 0) {
            try out.writer.writeAll("\n");
        } else {
            try out.writer.writeAll(",\n");
        }

        try out.writer.print(
            "    {{\"key\":\"{s}\",\"group\":\"{s}\",\"root_path\":\"{s}\"}}",
            .{ app.key, app.group.manifestName(), app.root_path },
        );
        emitted += 1;
    }

    if (emitted != 0) {
        try out.writer.writeAll("\n");
    }
    try out.writer.writeAll("  ]\n}\n");

    return try allocator.dupe(u8, out.writer.buffered());
}
