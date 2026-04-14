const std = @import("std");
const app_dep_hashes = @import("app_dep_hashes.zig");
const config = @import("config.zig");
const discover_apps = @import("discover_apps.zig");
const fingerprint = @import("fingerprint.zig");
const render_zon = @import("render_zon.zig");
const write_manifest = @import("write_manifest.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var repo_root_arg: []const u8 = ".";
    var build_dir_arg: []const u8 = ".build";

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--repo-root")) {
            i += 1;
            if (i >= args.len) return usage();
            repo_root_arg = args[i];
        } else if (std.mem.eql(u8, arg, "--build-dir")) {
            i += 1;
            if (i >= args.len) return usage();
            build_dir_arg = args[i];
        } else if (std.mem.eql(u8, arg, "--help")) {
            return usage();
        } else {
            std.log.err("unknown argument: {s}", .{arg});
            return usage();
        }
    }

    if (std.fs.path.isAbsolute(build_dir_arg)) {
        std.log.err("--build-dir must be repo-root relative, got absolute path: {s}", .{build_dir_arg});
        return error.InvalidArgument;
    }

    const repo_root = try std.fs.cwd().realpathAlloc(allocator, repo_root_arg);
    defer allocator.free(repo_root);
    std.log.info("generating zon files for repo {s}", .{repo_root});

    var repo_dir = try std.fs.openDirAbsolute(repo_root, .{});
    defer repo_dir.close();

    std.log.info("loading generator config", .{});
    var package_json = try config.load(allocator, repo_dir);
    defer package_json.deinit();

    std.log.info("scanning app manifests", .{});
    const apps = try discover_apps.scan(allocator, repo_dir);
    defer discover_apps.deinitApps(allocator, apps);

    const host_platform = discover_apps.hostDesktopPlatform();
    std.log.info("discovered {d} apps; host desktop platform (log only) is {s}", .{ apps.len, @tagName(host_platform) });

    var package_hashes = try config.resolvePackageHashes(allocator, repo_dir, package_json.value, apps);
    defer package_hashes.deinit();

    std.log.info("syncing app build.zig.zon remote deps from package.json", .{});
    try app_dep_hashes.syncAppManifests(allocator, repo_dir, apps, &package_hashes);

    std.log.info("checking app package fingerprints", .{});
    for (apps, 0..) |app, idx| {
        std.log.info("checking app fingerprint ({d}/{d}): {s}", .{ idx + 1, apps.len, app.root_path });
        try fingerprint.refreshPackageManifest(allocator, repo_dir, app.root_path);
    }

    const root_manifest_rel = try std.fmt.allocPrint(allocator, "{s}/gen_zon_files/root_apps_manifest.json", .{build_dir_arg});
    defer allocator.free(root_manifest_rel);
    const esp_manifest_rel = try std.fmt.allocPrint(allocator, "{s}/gen_zon_files/esp_apps_manifest.json", .{build_dir_arg});
    defer allocator.free(esp_manifest_rel);
    const desktop_manifest_rel = try std.fmt.allocPrint(allocator, "{s}/gen_zon_files/desktop_apps_manifest.json", .{build_dir_arg});
    defer allocator.free(desktop_manifest_rel);
    const root_stage_rel = try std.fmt.allocPrint(allocator, "{s}/zon/root/build.zig.zon", .{build_dir_arg});
    defer allocator.free(root_stage_rel);
    const esp_stage_rel = try std.fmt.allocPrint(allocator, "{s}/zon/esp/build.zig.zon", .{build_dir_arg});
    defer allocator.free(esp_stage_rel);
    const desktop_stage_rel = try std.fmt.allocPrint(allocator, "{s}/zon/desktop/build.zig.zon", .{build_dir_arg});
    defer allocator.free(desktop_stage_rel);

    std.log.info("rendering filtered app manifests", .{});
    const root_manifest_bytes = try write_manifest.renderSupportingAny(allocator, apps, &discover_apps.desktop_repo_platforms);
    defer allocator.free(root_manifest_bytes);
    try writeRepoFile(repo_dir, root_manifest_rel, root_manifest_bytes);

    const esp_manifest_bytes = try write_manifest.render(allocator, apps, .esp);
    defer allocator.free(esp_manifest_bytes);
    try writeRepoFile(repo_dir, esp_manifest_rel, esp_manifest_bytes);

    const desktop_manifest_bytes = try write_manifest.renderSupportingAny(allocator, apps, &discover_apps.desktop_repo_platforms);
    defer allocator.free(desktop_manifest_bytes);
    try writeRepoFile(repo_dir, desktop_manifest_rel, desktop_manifest_bytes);

    std.log.info("rendering root build.zig.zon", .{});
    const root_zon = try render_zon.render(allocator, .root, package_json.value, package_hashes, apps);
    defer allocator.free(root_zon);
    try writeMirroredPackageOutput(allocator, repo_dir, root_stage_rel, "build.zig.zon", ".", root_zon);

    std.log.info("rendering esp/build.zig.zon", .{});
    const esp_zon = try render_zon.render(allocator, .esp, package_json.value, package_hashes, apps);
    defer allocator.free(esp_zon);
    try writeMirroredPackageOutput(allocator, repo_dir, esp_stage_rel, "esp/build.zig.zon", "esp", esp_zon);

    std.log.info("rendering desktop/build.zig.zon", .{});
    const desktop_zon = try render_zon.render(allocator, .desktop, package_json.value, package_hashes, apps);
    defer allocator.free(desktop_zon);
    try writeMirroredPackageOutput(allocator, repo_dir, desktop_stage_rel, "desktop/build.zig.zon", "desktop", desktop_zon);
}

fn usage() !void {
    std.debug.print(
        \\usage: gen_zon_files [--repo-root PATH] [--build-dir PATH]
        \\
        \\  --repo-root  repository root to scan and update (default: .)
        \\  --build-dir  repo-relative staging directory (default: .build)
        \\
    , .{});
}

fn writeMirroredOutput(
    repo_dir: std.fs.Dir,
    stage_rel_path: []const u8,
    mirror_rel_path: []const u8,
    bytes: []const u8,
) !void {
    try writeRepoFile(repo_dir, stage_rel_path, bytes);
    try writeRepoFile(repo_dir, mirror_rel_path, bytes);
}

fn writeMirroredPackageOutput(
    allocator: std.mem.Allocator,
    repo_dir: std.fs.Dir,
    stage_rel_path: []const u8,
    mirror_rel_path: []const u8,
    package_rel_path: []const u8,
    bytes: []const u8,
) !void {
    const existing_mirror_bytes = readRepoFileAlloc(allocator, repo_dir, mirror_rel_path) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    defer if (existing_mirror_bytes) |value| allocator.free(value);
    const mirror_unchanged = if (existing_mirror_bytes) |value|
        std.mem.eql(u8, value, bytes)
    else
        false;

    try writeMirroredOutput(repo_dir, stage_rel_path, mirror_rel_path, bytes);
    if (mirror_unchanged) {
        std.log.info("skipping package fingerprint refresh for {s}; manifest bytes unchanged", .{
            package_rel_path,
        });
        return;
    }
    std.log.info("refreshing package fingerprint for {s}", .{package_rel_path});
    try fingerprint.refreshPackageManifest(allocator, repo_dir, package_rel_path);

    const refreshed_bytes = try readRepoFileAlloc(allocator, repo_dir, mirror_rel_path);
    defer allocator.free(refreshed_bytes);
    try writeRepoFile(repo_dir, stage_rel_path, refreshed_bytes);
}

fn writeRepoFile(repo_dir: std.fs.Dir, rel_path: []const u8, bytes: []const u8) !void {
    if (std.fs.path.dirname(rel_path)) |dir_name| {
        try repo_dir.makePath(dir_name);
    }

    var file = try repo_dir.createFile(rel_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
    std.log.info("wrote {s}", .{rel_path});
}

fn readRepoFileAlloc(
    allocator: std.mem.Allocator,
    repo_dir: std.fs.Dir,
    rel_path: []const u8,
) ![]u8 {
    var file = try repo_dir.openFile(rel_path, .{});
    defer file.close();
    return file.readToEndAlloc(allocator, 1024 * 1024);
}
