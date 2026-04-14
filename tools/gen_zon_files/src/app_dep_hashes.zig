const std = @import("std");
const config = @import("config.zig");
const discover_apps = @import("discover_apps.zig");

const hash_needle = ".hash = \"";
const url_needle = ".url = \"";

const TextRep = struct {
    start: usize,
    end: usize,
    text: []const u8,
};

/// Rewrites each app `build.zig.zon` so remote dependency `.url` / `.hash` match `package.json`
/// (via `PackageHashes`). Does not add or remove dependency keys.
pub fn syncAppManifests(
    allocator: std.mem.Allocator,
    repo_dir: std.fs.Dir,
    apps: []const discover_apps.App,
    package_hashes: *const config.PackageHashes,
) !void {
    for (apps, 0..) |app, idx| {
        std.log.info("syncing app remote deps from package.json ({d}/{d}): {s}", .{
            idx + 1,
            apps.len,
            app.root_path,
        });
        const rel_path = try std.fmt.allocPrint(allocator, "{s}/build.zig.zon", .{app.root_path});
        defer allocator.free(rel_path);
        try syncOneManifest(allocator, repo_dir, rel_path, package_hashes);
    }
}

fn syncOneManifest(
    allocator: std.mem.Allocator,
    repo_dir: std.fs.Dir,
    manifest_rel_path: []const u8,
    package_hashes: *const config.PackageHashes,
) !void {
    var file = try repo_dir.openFile(manifest_rel_path, .{});
    defer file.close();

    const old_bytes = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(old_bytes);

    var edits = std.ArrayListUnmanaged(TextRep){};
    defer edits.deinit(allocator);

    const DepBlock = struct {
        needle: []const u8,
        dep: config.ResolvedRemoteDep,
    };
    const dep_blocks = [_]DepBlock{
        .{ .needle = ".embed_zig = .{", .dep = package_hashes.embed_zig },
        .{ .needle = ".lvgl = .{", .dep = package_hashes.lvgl },
        .{ .needle = ".speexdsp = .{", .dep = package_hashes.speexdsp },
        .{ .needle = ".opus = .{", .dep = package_hashes.opus },
        .{ .needle = ".portaudio = .{", .dep = package_hashes.portaudio },
        .{ .needle = ".stb_truetype = .{", .dep = package_hashes.stb_truetype },
    };

    for (dep_blocks) |item| {
        try appendBlockUrlHashEdits(allocator, old_bytes, item.needle, item.dep, &edits);
    }

    if (edits.items.len == 0) {
        std.log.info("app manifest already matches package.json: {s}", .{manifest_rel_path});
        return;
    }

    const new_bytes = try applyTextReplacements(allocator, old_bytes, edits.items);
    defer allocator.free(new_bytes);

    var out = try repo_dir.createFile(manifest_rel_path, .{ .truncate = true });
    defer out.close();
    try out.writeAll(new_bytes);
    std.log.info("wrote app manifest synced to package.json: {s}", .{manifest_rel_path});
}

fn appendBlockUrlHashEdits(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    block_open_needle: []const u8,
    dep: config.ResolvedRemoteDep,
    edits: *std.ArrayListUnmanaged(TextRep),
) !void {
    const b = std.mem.indexOf(u8, bytes, block_open_needle) orelse return;
    const window_end = @min(bytes.len, b + 640);

    const url_key = std.mem.indexOfPos(u8, bytes, b, url_needle) orelse return error.InvalidAppManifest;
    if (url_key >= window_end) return error.InvalidAppManifest;
    const url_val_start = url_key + url_needle.len;
    const url_val_end = std.mem.indexOfScalarPos(u8, bytes, url_val_start, '"') orelse return error.InvalidAppManifest;

    const hash_key = std.mem.indexOfPos(u8, bytes, url_val_end, hash_needle) orelse return error.InvalidAppManifest;
    if (hash_key >= window_end) return error.InvalidAppManifest;
    const hash_val_start = hash_key + hash_needle.len;
    const hash_val_end = std.mem.indexOfScalarPos(u8, bytes, hash_val_start, '"') orelse return error.InvalidAppManifest;

    if (!std.mem.eql(u8, bytes[url_val_start..url_val_end], dep.url)) {
        try edits.append(allocator, .{
            .start = url_val_start,
            .end = url_val_end,
            .text = dep.url,
        });
    }
    if (!std.mem.eql(u8, bytes[hash_val_start..hash_val_end], dep.hash)) {
        try edits.append(allocator, .{
            .start = hash_val_start,
            .end = hash_val_end,
            .text = dep.hash,
        });
    }
}

fn applyTextReplacements(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    reps: []TextRep,
) ![]u8 {
    if (reps.len == 0) return allocator.dupe(u8, bytes);

    std.mem.sortUnstable(TextRep, reps, {}, struct {
        fn less(_: void, a: TextRep, b: TextRep) bool {
            return a.start < b.start;
        }
    }.less);

    for (reps[0 .. reps.len - 1], reps[1..]) |cur, next| {
        if (cur.end > next.start) return error.OverlappingTextRewrite;
    }

    var out = std.ArrayListUnmanaged(u8){};
    errdefer out.deinit(allocator);

    var cursor: usize = 0;
    for (reps) |r| {
        try out.appendSlice(allocator, bytes[cursor..r.start]);
        try out.appendSlice(allocator, r.text);
        cursor = r.end;
    }
    try out.appendSlice(allocator, bytes[cursor..]);

    return out.toOwnedSlice(allocator);
}
