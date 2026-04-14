const std = @import("std");

const fingerprint_marker = ".fingerprint = ";

pub fn refreshPackageManifest(
    allocator: std.mem.Allocator,
    repo_dir: std.fs.Dir,
    package_rel_path: []const u8,
) !void {
    const package_abs_path = try repo_dir.realpathAlloc(allocator, package_rel_path);
    defer allocator.free(package_abs_path);

    const suggested = try fetchSuggestedFingerprint(allocator, package_abs_path);
    defer if (suggested) |value| allocator.free(value);

    if (suggested) |value| {
        const manifest_rel_path = try manifestRelPath(allocator, package_rel_path);
        defer allocator.free(manifest_rel_path);

        try rewriteFingerprint(allocator, repo_dir, manifest_rel_path, value);
        std.log.info("updated {s} fingerprint to {s}", .{ manifest_rel_path, value });

        if (try fetchSuggestedFingerprint(allocator, package_abs_path)) |retry_value| {
            defer allocator.free(retry_value);
            std.log.err("manifest {s} still suggests fingerprint {s}", .{ manifest_rel_path, retry_value });
            return error.InvalidFingerprintRewrite;
        }
    } else {
        std.log.info("fingerprint ok for {s}", .{package_rel_path});
    }
}

fn fetchSuggestedFingerprint(
    allocator: std.mem.Allocator,
    package_abs_path: []const u8,
) !?[]u8 {
    const zig_exe = std.posix.getenv("ZIG") orelse "zig";

    // `zig fetch` on a large workspace copies the tree into the global package cache and can hit
    // `error.NameTooLong` on Linux CI. `zig build -h` loads `build.zig.zon`, validates the
    // fingerprint, and exits without that copy; stderr still contains "use this value: ..." when
    // the fingerprint is wrong.
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ zig_exe, "build", "-h" },
        .cwd = package_abs_path,
        .max_output_bytes = 1024 * 1024,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| {
            if (code == 0) return null;
        },
        else => {},
    }

    if (extractSuggestedFingerprint(result.stderr)) |value| {
        return try allocator.dupe(u8, value);
    }

    std.log.err("`{s} build -h` (cwd {s}) failed\nstdout:\n{s}\nstderr:\n{s}", .{
        zig_exe,
        package_abs_path,
        result.stdout,
        result.stderr,
    });
    return error.ZigFetchFailed;
}

fn extractSuggestedFingerprint(stderr: []const u8) ?[]const u8 {
    const needle = "use this value: ";
    const start = std.mem.indexOf(u8, stderr, needle) orelse return null;
    const value_start = start + needle.len;
    const value_end = std.mem.indexOfAnyPos(u8, stderr, value_start, " \t\r\n") orelse stderr.len;
    return stderr[value_start..value_end];
}

fn manifestRelPath(allocator: std.mem.Allocator, package_rel_path: []const u8) ![]u8 {
    if (std.mem.eql(u8, package_rel_path, ".")) {
        return allocator.dupe(u8, "build.zig.zon");
    }
    return std.fmt.allocPrint(allocator, "{s}/build.zig.zon", .{package_rel_path});
}

fn rewriteFingerprint(
    allocator: std.mem.Allocator,
    repo_dir: std.fs.Dir,
    manifest_rel_path: []const u8,
    new_fingerprint: []const u8,
) !void {
    var file = try repo_dir.openFile(manifest_rel_path, .{});
    defer file.close();

    const old_bytes = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(old_bytes);

    const marker_idx = std.mem.indexOf(u8, old_bytes, fingerprint_marker) orelse
        return error.MissingFingerprintField;
    const value_start = marker_idx + fingerprint_marker.len;
    const value_end = std.mem.indexOfAnyPos(u8, old_bytes, value_start, ",\n") orelse
        return error.InvalidFingerprintField;

    const new_bytes = try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{
        old_bytes[0..value_start],
        new_fingerprint,
        old_bytes[value_end..],
    });
    defer allocator.free(new_bytes);

    var output = try repo_dir.createFile(manifest_rel_path, .{ .truncate = true });
    defer output.close();
    try output.writeAll(new_bytes);
}
