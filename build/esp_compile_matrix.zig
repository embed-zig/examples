//! Host tool: run the ESP compile matrix for every supported optimize mode.
//!
//! For each `optimize/app` pair this tool prepares an isolated sandbox under
//! `esp/.matrix/<Optimize>/<app>/`, runs `zig build -Dapp=… -Doptimize=…`
//! there, and writes one status file per optimize mode plus an index:
//! - `esp/Debug_BUILD_STATUS.md`
//! - `esp/ReleaseSafe_BUILD_STATUS.md`
//! - `esp/ReleaseFast_BUILD_STATUS.md`
//! - `esp/ReleaseSmall_BUILD_STATUS.md`
//! - `esp/BUILD_STATUS.md`
//!
//! Environment (set by root `build.zig`):
//! - `COMPAT_TESTS_ROOT` — absolute repo root
//! - `IDF_PATH` — ESP-IDF root (from `zig build esp -Didf=…`)
//! - `COMPAT_TESTS_MANIFEST` — generated app manifest path

const zig_std = @import("std");
const apps_manifest = @import("apps_manifest.zig");

const run_log = zig_std.log.scoped(.compat_tests);
const optimize_modes = [_]OptimizeMode{
    .Debug,
    .ReleaseSafe,
    .ReleaseFast,
    .ReleaseSmall,
};

const AppGroup = enum {
    unit,
    integration,
};

const OptimizeMode = enum {
    Debug,
    ReleaseSafe,
    ReleaseFast,
    ReleaseSmall,

    fn tag(self: OptimizeMode) []const u8 {
        return @tagName(self);
    }

    fn optionArg(self: OptimizeMode, allocator: zig_std.mem.Allocator) ![]const u8 {
        return zig_std.fmt.allocPrint(allocator, "-Doptimize={s}", .{self.tag()});
    }

    fn statusFileName(self: OptimizeMode) []const u8 {
        return switch (self) {
            .Debug => "Debug_BUILD_STATUS.md",
            .ReleaseSafe => "ReleaseSafe_BUILD_STATUS.md",
            .ReleaseFast => "ReleaseFast_BUILD_STATUS.md",
            .ReleaseSmall => "ReleaseSmall_BUILD_STATUS.md",
        };
    }
};

const Workspace = struct {
    root_path: []const u8,
    elf_layout_path: []const u8,
};

const AppStatus = struct {
    app: []const u8,
    group: AppGroup,
    ok: bool,
    summary: ?[]const u8,
    elapsed_ms: u64,
    bin_size_bytes: ?u64,
};

const BuildRunResult = struct {
    ok: bool,
    summary: ?[]const u8,
    elapsed_ms: u64,
    bin_size_bytes: ?u64,
};

fn groupForApp(app: []const u8) AppGroup {
    if (zig_std.mem.startsWith(u8, app, "integration-test_")) return .integration;
    return .unit;
}

fn lineContainsAny(line: []const u8, needles: []const []const u8) bool {
    for (needles) |needle| {
        if (zig_std.mem.indexOf(u8, line, needle) != null) return true;
    }
    return false;
}

fn lineHasNoisePrefix(line: []const u8) bool {
    const prefixes = [_][]const u8{
        "-- ",
        "Executing ",
        "Running ",
        "warning:",
        "info:",
        "esptool.py ",
        "SHA digest",
        "Wrote ",
        "Program Headers:",
        "Section to Segment mapping:",
        "Type      Offset",
        "LOAD      ",
        "GNU_STACK ",
        "Segment Sections...",
        "+- ",
        "|  +- ",
        "Build Summary:",
    };
    for (prefixes) |prefix| {
        if (zig_std.mem.startsWith(u8, line, prefix)) return true;
    }
    return false;
}

fn firstMatchingLine(text: []const u8, needles: []const []const u8) ?[]const u8 {
    var iter = zig_std.mem.splitScalar(u8, text, '\n');
    while (iter.next()) |raw_line| {
        const line = zig_std.mem.trim(u8, raw_line, " \t\r\n");
        if (line.len == 0) continue;
        if (lineContainsAny(line, needles)) return line;
    }
    return null;
}

fn firstInterestingLine(text: []const u8) ?[]const u8 {
    const preferred = [_][]const u8{
        "file exists in modules",
        "Unsupported operating system",
        "undefined reference",
        "ld returned 1 exit status",
        "not found",
        "panic:",
        "error:",
    };
    if (firstMatchingLine(text, &preferred)) |line| return line;

    var iter = zig_std.mem.splitScalar(u8, text, '\n');
    while (iter.next()) |raw_line| {
        const line = zig_std.mem.trim(u8, raw_line, " \t\r\n");
        if (line.len == 0) continue;
        if (lineHasNoisePrefix(line)) continue;
        return line;
    }
    return null;
}

fn summarizeFailure(allocator: zig_std.mem.Allocator, stderr: []const u8, stdout: []const u8, term: zig_std.process.Child.Term) ![]const u8 {
    if (firstInterestingLine(stderr)) |line| return allocator.dupe(u8, line);
    if (firstInterestingLine(stdout)) |line| return allocator.dupe(u8, line);

    switch (term) {
        .Exited => |code| return zig_std.fmt.allocPrint(allocator, "zig build exited with code {d}", .{code}),
        else => return allocator.dupe(u8, "zig build terminated unexpectedly"),
    }
}

fn printCapturedOutput(stdout: []const u8, stderr: []const u8) void {
    zig_std.fs.File.stdout().writeAll(stdout) catch {};
    zig_std.fs.File.stderr().writeAll(stderr) catch {};
}

fn runOneEspBuild(
    allocator: zig_std.mem.Allocator,
    repo_root: []const u8,
    optimize: OptimizeMode,
    app: []const u8,
) !BuildRunResult {
    const temp_alloc = zig_std.heap.page_allocator;
    const workspace = try prepareWorkspace(allocator, repo_root, optimize, app);
    var timer = try zig_std.time.Timer.start();

    const app_arg = try zig_std.fmt.allocPrint(temp_alloc, "-Dapp={s}", .{app});
    defer temp_alloc.free(app_arg);
    const optimize_arg = try optimize.optionArg(temp_alloc);
    defer temp_alloc.free(optimize_arg);

    const child_result = zig_std.process.Child.run(.{
        .allocator = temp_alloc,
        .argv = &.{
            "zig",
            "build",
            app_arg,
            optimize_arg,
            "--cache-dir",
            ".zig-cache",
            "--prefix",
            "zig-out",
        },
        .cwd = workspace.root_path,
        .max_output_bytes = 64 * 1024 * 1024,
    }) catch |err| {
        return .{
            .ok = false,
            .summary = try zig_std.fmt.allocPrint(allocator, "failed to execute zig build: {}", .{err}),
            .elapsed_ms = timer.read() / zig_std.time.ns_per_ms,
            .bin_size_bytes = null,
        };
    };
    defer temp_alloc.free(child_result.stdout);
    defer temp_alloc.free(child_result.stderr);

    printCapturedOutput(child_result.stdout, child_result.stderr);

    const elapsed_ms = timer.read() / zig_std.time.ns_per_ms;
    switch (child_result.term) {
        .Exited => |code| if (code == 0) {
            const bin_size_bytes = readBinSizeFromElfLayout(allocator, workspace.elf_layout_path) catch |err| blk: {
                run_log.warn("could not read bin size for /{s}: {}", .{ app, err });
                break :blk null;
            };
            return .{
                .ok = true,
                .summary = null,
                .elapsed_ms = elapsed_ms,
                .bin_size_bytes = bin_size_bytes,
            };
        },
        else => {},
    }

    const bin_size_bytes = readBinSizeFromElfLayout(allocator, workspace.elf_layout_path) catch null;
    return .{
        .ok = false,
        .summary = try summarizeFailure(allocator, child_result.stderr, child_result.stdout, child_result.term),
        .elapsed_ms = elapsed_ms,
        .bin_size_bytes = bin_size_bytes,
    };
}

fn printDuration(writer: anytype, elapsed_ms: u64) !void {
    const tenths = elapsed_ms / 100;
    try writer.print("{d}.{d:0>1}s", .{ tenths / 10, tenths % 10 });
}

fn printMiB(writer: anytype, bytes: u64) !void {
    const mib_bytes: u64 = 1024 * 1024;
    const scaled = (bytes * 100 + mib_bytes / 2) / mib_bytes;
    try writer.print("{d}.{d:0>2} MiB", .{ scaled / 100, scaled % 100 });
}

fn deletePathIfPresent(absolute_path: []const u8) !void {
    zig_std.fs.deleteFileAbsolute(absolute_path) catch |err| switch (err) {
        error.FileNotFound => {
            zig_std.fs.deleteTreeAbsolute(absolute_path) catch |tree_err| switch (tree_err) {
                error.FileNotFound => {},
                else => return tree_err,
            };
        },
        error.IsDir => {
            zig_std.fs.deleteTreeAbsolute(absolute_path) catch |tree_err| switch (tree_err) {
                error.FileNotFound => {},
                else => return tree_err,
            };
        },
        else => return err,
    };
}

fn ensureParentDir(absolute_path: []const u8) !void {
    const parent = zig_std.fs.path.dirname(absolute_path) orelse return error.InvalidPath;
    try zig_std.fs.cwd().makePath(parent);
}

fn copyFileIntoSandbox(source_path: []const u8, dest_path: []const u8) !void {
    try ensureParentDir(dest_path);
    try zig_std.fs.copyFileAbsolute(source_path, dest_path, .{});
}

fn copyTreeIntoSandbox(
    allocator: zig_std.mem.Allocator,
    source_dir_path: []const u8,
    dest_dir_path: []const u8,
) !void {
    try zig_std.fs.cwd().makePath(dest_dir_path);

    var source_dir = try zig_std.fs.openDirAbsolute(source_dir_path, .{ .iterate = true });
    defer source_dir.close();

    var walker = try source_dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        const source_path = try zig_std.fs.path.join(allocator, &.{ source_dir_path, entry.path });
        defer allocator.free(source_path);
        const dest_path = try zig_std.fs.path.join(allocator, &.{ dest_dir_path, entry.path });
        defer allocator.free(dest_path);

        switch (entry.kind) {
            .directory => try zig_std.fs.cwd().makePath(dest_path),
            .file => try copyFileIntoSandbox(source_path, dest_path),
            .sym_link => {
                var link_target_buf: [zig_std.fs.max_path_bytes]u8 = undefined;
                const link_target = try zig_std.fs.readLinkAbsolute(source_path, &link_target_buf);
                try zig_std.fs.symLinkAbsolute(link_target, dest_path, .{});
            },
            else => {},
        }
    }
}

fn optimizeRootPath(
    allocator: zig_std.mem.Allocator,
    repo_root: []const u8,
    optimize: OptimizeMode,
) ![]const u8 {
    return zig_std.fs.path.join(allocator, &.{ repo_root, "esp", ".matrix", optimize.tag() });
}

fn matrixRootPath(allocator: zig_std.mem.Allocator, repo_root: []const u8) ![]const u8 {
    return zig_std.fs.path.join(allocator, &.{ repo_root, "esp", ".matrix" });
}

fn sandboxRootPath(
    allocator: zig_std.mem.Allocator,
    repo_root: []const u8,
    optimize: OptimizeMode,
    app: []const u8,
) ![]const u8 {
    return zig_std.fs.path.join(allocator, &.{ repo_root, "esp", ".matrix", optimize.tag(), app });
}

fn ensureOptimizeSharedLinks(
    allocator: zig_std.mem.Allocator,
    repo_root: []const u8,
    optimize_root_path: []const u8,
) !void {
    try zig_std.fs.cwd().makePath(optimize_root_path);
    const matrix_root_path = try matrixRootPath(allocator, repo_root);
    try zig_std.fs.cwd().makePath(matrix_root_path);

    const apps_path = try zig_std.fs.path.join(allocator, &.{ repo_root, "apps" });
    const apps_link_path = try zig_std.fs.path.join(allocator, &.{ optimize_root_path, "apps" });
    try deletePathIfPresent(apps_link_path);
    try zig_std.fs.symLinkAbsolute(apps_path, apps_link_path, .{ .is_directory = true });

    const vendor_path = try zig_std.fs.path.join(allocator, &.{ repo_root, "vendor" });
    const vendor_link_path = try zig_std.fs.path.join(allocator, &.{ optimize_root_path, "vendor" });
    try deletePathIfPresent(vendor_link_path);
    try zig_std.fs.symLinkAbsolute(vendor_path, vendor_link_path, .{ .is_directory = true });
}

fn stageEspWorkspace(
    allocator: zig_std.mem.Allocator,
    repo_root: []const u8,
    sandbox_root_path: []const u8,
) !void {
    const repo_esp_path = try zig_std.fs.path.join(allocator, &.{ repo_root, "esp" });

    const build_zig_path = try zig_std.fs.path.join(allocator, &.{ repo_esp_path, "build.zig" });
    const build_zig_dest = try zig_std.fs.path.join(allocator, &.{ sandbox_root_path, "build.zig" });
    try copyFileIntoSandbox(build_zig_path, build_zig_dest);

    const build_zig_zon_path = try zig_std.fs.path.join(allocator, &.{ repo_esp_path, "build.zig.zon" });
    const build_zig_zon_dest = try zig_std.fs.path.join(allocator, &.{ sandbox_root_path, "build.zig.zon" });
    try copyFileIntoSandbox(build_zig_zon_path, build_zig_zon_dest);

    const dir_names = [_][]const u8{ "build", "board", "c_helper", "src" };
    for (dir_names) |dir_name| {
        const source_dir_path = try zig_std.fs.path.join(allocator, &.{ repo_esp_path, dir_name });
        const dest_dir_path = try zig_std.fs.path.join(allocator, &.{ sandbox_root_path, dir_name });
        try copyTreeIntoSandbox(allocator, source_dir_path, dest_dir_path);
    }
}

fn prepareWorkspace(
    allocator: zig_std.mem.Allocator,
    repo_root: []const u8,
    optimize: OptimizeMode,
    app: []const u8,
) !Workspace {
    const optimize_root_path = try optimizeRootPath(allocator, repo_root, optimize);
    try ensureOptimizeSharedLinks(allocator, repo_root, optimize_root_path);

    const sandbox_root_path = try sandboxRootPath(allocator, repo_root, optimize, app);
    try deletePathIfPresent(sandbox_root_path);
    try zig_std.fs.cwd().makePath(sandbox_root_path);
    try stageEspWorkspace(allocator, repo_root, sandbox_root_path);

    const elf_layout_path = try zig_std.fs.path.join(allocator, &.{ sandbox_root_path, ".build", "elf_layout.txt" });
    return .{
        .root_path = sandbox_root_path,
        .elf_layout_path = elf_layout_path,
    };
}

fn writeStatusSection(writer: anytype, title: []const u8, results: []const AppStatus, group: AppGroup) !void {
    try writer.print("## {s}\n\n", .{title});
    for (results) |result| {
        if (result.group != group) continue;
        if (result.summary) |summary| {
            try writer.print("- [{s}] `{s}`", .{ if (result.ok) "x" else " ", result.app });
            if (result.bin_size_bytes) |bytes| {
                try writer.writeAll(" — ");
                try printMiB(writer, bytes);
            }
            try writer.print(" — {s}\n", .{summary});
        } else {
            try writer.print("- [{s}] `{s}`", .{ if (result.ok) "x" else " ", result.app });
            if (result.bin_size_bytes) |bytes| {
                try writer.writeAll(" — ");
                try printMiB(writer, bytes);
            }
            try writer.writeByte('\n');
        }
    }
    try writer.writeByte('\n');
}

fn readBinSizeFromElfLayout(allocator: zig_std.mem.Allocator, elf_layout_path: []const u8) !u64 {
    var file = try zig_std.fs.openFileAbsolute(elf_layout_path, .{});
    defer file.close();

    const bytes = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(bytes);

    var lines = zig_std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        const trimmed = zig_std.mem.trim(u8, line, " \t\r");
        if (!zig_std.mem.startsWith(u8, trimmed, "#   ")) continue;
        if (!zig_std.mem.endsWith(u8, trimmed, " bytes")) continue;
        if (zig_std.mem.indexOf(u8, trimmed, ".bin: ") == null) continue;
        if (zig_std.mem.indexOf(u8, trimmed, "bootloader.bin: ") != null) continue;

        const colon_idx = zig_std.mem.lastIndexOf(u8, trimmed, ": ") orelse continue;
        const suffix = trimmed[colon_idx + 2 ..];
        const bytes_text = suffix[0 .. suffix.len - " bytes".len];
        return try zig_std.fmt.parseInt(u64, bytes_text, 10);
    }

    return error.BinSizeNotFound;
}

fn writeBuildStatus(
    allocator: zig_std.mem.Allocator,
    repo_root: []const u8,
    idf_path: []const u8,
    optimize: OptimizeMode,
    results: []const AppStatus,
    total_elapsed_ms: u64,
) !void {
    const alloc = zig_std.heap.page_allocator;
    const status_path = try zig_std.fs.path.join(alloc, &.{ repo_root, "esp", optimize.statusFileName() });
    defer alloc.free(status_path);
    const workspace_root_path = try optimizeRootPath(allocator, repo_root, optimize);

    var total_count: usize = 0;
    var passed_count: usize = 0;
    var failed_count: usize = 0;
    for (results) |result| {
        total_count += 1;
        if (result.ok) {
            passed_count += 1;
        } else {
            failed_count += 1;
        }
    }

    var file = try zig_std.fs.createFileAbsolute(status_path, .{ .truncate = true });
    defer file.close();
    var buf = zig_std.ArrayList(u8).empty;
    defer buf.deinit(alloc);
    const writer = buf.writer(alloc);

    try writer.writeAll("# ESP `zig build -Dapp=…` Status\n\n");
    try writer.writeAll("> Auto-generated by the root `zig build esp` matrix. Do not edit by hand.\n\n");
    try writer.writeAll("## Summary\n\n");
    try writer.print("- Command: `zig build esp -Didf={s}`\n", .{idf_path});
    try writer.print("- Apps: {d}\n", .{total_count});
    try writer.print("- Passed: {d}\n", .{passed_count});
    try writer.print("- Failed: {d}\n", .{failed_count});
    try writer.print("- Optimize: `{s}`\n", .{optimize.tag()});
    try writer.print("- Workspace root: `esp/.matrix/{s}/`\n", .{optimize.tag()});
    try writer.writeAll("- Duration: ");
    try printDuration(writer, total_elapsed_ms);
    try writer.writeAll("\n");
    try writer.print(
        "- Bin size comes from each app workspace `.bin` entry under `{s}/<app>/.build/elf_layout.txt`.\n",
        .{workspaceRootRel(workspace_root_path, repo_root)},
    );
    try writer.writeAll("- Failure summaries are best-effort excerpts from each app's `zig build` output.\n\n");

    try writeStatusSection(writer, "Unit", results, .unit);
    try writeStatusSection(writer, "Integration", results, .integration);

    try file.writeAll(buf.items);
    run_log.info("wrote {s}", .{status_path});
}

fn workspaceRootRel(workspace_root_path: []const u8, repo_root: []const u8) []const u8 {
    if (zig_std.mem.startsWith(u8, workspace_root_path, repo_root) and workspace_root_path.len > repo_root.len + 1) {
        return workspace_root_path[repo_root.len + 1 ..];
    }
    return workspace_root_path;
}

fn writeBuildStatusIndex(repo_root: []const u8) !void {
    const alloc = zig_std.heap.page_allocator;
    const status_path = try zig_std.fs.path.join(alloc, &.{ repo_root, "esp", "BUILD_STATUS.md" });
    defer alloc.free(status_path);

    var file = try zig_std.fs.createFileAbsolute(status_path, .{ .truncate = true });
    defer file.close();
    var buf = zig_std.ArrayList(u8).empty;
    defer buf.deinit(alloc);
    const writer = buf.writer(alloc);

    try writer.writeAll("# ESP Build Status Index\n\n");
    try writer.writeAll("> Auto-generated by the root `zig build esp` matrix. Do not edit by hand.\n\n");
    try writer.writeAll("## Optimize Variants\n\n");
    for (optimize_modes) |optimize| {
        try writer.print("- [`{s}`]({s})\n", .{ optimize.tag(), optimize.statusFileName() });
    }
    try writer.writeAll("\n## Matrix Layout\n\n");
    try writer.writeAll("- Each app runs in its own sandbox under `esp/.matrix/<Optimize>/<app>/`.\n");
    try writer.writeAll("- That sandbox owns its own `.build`, `.zig-cache`, and `zig-out`, so optimize modes and apps do not trample one another.\n");

    try file.writeAll(buf.items);
    run_log.info("wrote {s}", .{status_path});
}

pub fn main() !void {
    const repo_root = zig_std.posix.getenv("COMPAT_TESTS_ROOT") orelse {
        zig_std.log.err("COMPAT_TESTS_ROOT is not set", .{});
        return error.MissingEnv;
    };
    const idf_path = zig_std.posix.getenv("IDF_PATH") orelse {
        zig_std.log.err("IDF_PATH is not set (use zig build esp -Didf=…)", .{});
        return error.MissingEnv;
    };
    const manifest_path = zig_std.posix.getenv("COMPAT_TESTS_MANIFEST") orelse {
        zig_std.log.err("COMPAT_TESTS_MANIFEST is not set", .{});
        return error.MissingEnv;
    };

    var arena = zig_std.heap.ArenaAllocator.init(zig_std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var manifest = try apps_manifest.loadFromAbsolutePath(alloc, manifest_path);
    defer manifest.deinit();
    const entries = manifest.parsed.value.apps;

    var has_failures = false;

    for (optimize_modes) |optimize| {
        run_log.info("=== optimize {s} ===", .{optimize.tag()});
        var total_timer = try zig_std.time.Timer.start();
        const results = try alloc.alloc(AppStatus, entries.len);

        for (entries, 0..) |entry, idx| {
            const app = entry.key;
            run_log.info(">>> [{s}] /{s} start ({d}/{d})", .{ optimize.tag(), app, idx + 1, entries.len });
            const build_result = try runOneEspBuild(alloc, repo_root, optimize, app);
            results[idx] = .{
                .app = app,
                .group = groupForApp(app),
                .ok = build_result.ok,
                .summary = build_result.summary,
                .elapsed_ms = build_result.elapsed_ms,
                .bin_size_bytes = build_result.bin_size_bytes,
            };
            if (build_result.ok) {
                run_log.info("<<< [{s}] /{s} done in {d}ms", .{ optimize.tag(), app, build_result.elapsed_ms });
            } else {
                has_failures = true;
                run_log.err("!!! [{s}] /{s} failed in {d}ms", .{ optimize.tag(), app, build_result.elapsed_ms });
            }
        }

        try writeBuildStatus(alloc, repo_root, idf_path, optimize, results, total_timer.read() / zig_std.time.ns_per_ms);
    }

    try writeBuildStatusIndex(repo_root);

    if (has_failures) zig_std.process.exit(1);
}
