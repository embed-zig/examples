const std = @import("std");
const discover_apps = @import("discover_apps.zig");

pub const PackageJson = struct {
    name: []const u8,
    version: []const u8,
    private: bool = true,
    dependencies: Dependencies,
    zon: Zon,

    pub const Zon = struct {
        minimum_zig_version: []const u8,
    };

    pub const Dependencies = struct {
        @"embed-zig": []const u8,
        esp: []const u8,
        lvgl: []const u8,
        speexdsp: []const u8,
        opus: []const u8,
        portaudio: []const u8,
        @"stb-truetype": []const u8,
    };
};

pub fn load(allocator: std.mem.Allocator, repo_dir: std.fs.Dir) !std.json.Parsed(PackageJson) {
    var file = try repo_dir.openFile("tools/gen_zon_files/package.json", .{});
    defer file.close();

    const bytes = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(bytes);

    return std.json.parseFromSlice(PackageJson, allocator, bytes, .{
        .allocate = .alloc_always,
    });
}

pub fn resolveHashFromUrl(
    allocator: std.mem.Allocator,
    url: []const u8,
) ![]u8 {
    const zig_exe = std.posix.getenv("ZIG") orelse "zig";
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ zig_exe, "fetch", url },
        .max_output_bytes = 1024 * 1024,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                std.log.err("`{s} fetch {s}` failed with exit code {d}\n{s}", .{
                    zig_exe,
                    url,
                    code,
                    result.stderr,
                });
                return error.ZigFetchFailed;
            }
        },
        else => return error.ZigFetchFailed,
    }

    const trimmed = std.mem.trim(u8, result.stdout, " \t\r\n");
    if (trimmed.len == 0) return error.ZigFetchFailed;
    return allocator.dupe(u8, trimmed);
}

pub const ResolvedRemoteDep = struct {
    url: []u8,
    hash: []u8,
};

/// Canonical tarball URL + Zig package hash for every remote dependency in `package.json`.
pub const PackageHashes = struct {
    allocator: std.mem.Allocator,
    embed_zig: ResolvedRemoteDep,
    esp: ResolvedRemoteDep,
    lvgl: ResolvedRemoteDep,
    speexdsp: ResolvedRemoteDep,
    opus: ResolvedRemoteDep,
    portaudio: ResolvedRemoteDep,
    stb_truetype: ResolvedRemoteDep,

    pub fn deinit(self: *PackageHashes) void {
        self.allocator.free(self.embed_zig.url);
        self.allocator.free(self.embed_zig.hash);
        self.allocator.free(self.esp.url);
        self.allocator.free(self.esp.hash);
        self.allocator.free(self.lvgl.url);
        self.allocator.free(self.lvgl.hash);
        self.allocator.free(self.speexdsp.url);
        self.allocator.free(self.speexdsp.hash);
        self.allocator.free(self.opus.url);
        self.allocator.free(self.opus.hash);
        self.allocator.free(self.portaudio.url);
        self.allocator.free(self.portaudio.hash);
        self.allocator.free(self.stb_truetype.url);
        self.allocator.free(self.stb_truetype.hash);
    }
};

pub fn resolvePackageHashes(
    allocator: std.mem.Allocator,
    repo_dir: std.fs.Dir,
    cfg: PackageJson,
    apps: []const discover_apps.App,
) !PackageHashes {
    std.log.info("resolving remote dependency URLs and hashes from package.json", .{});

    const embed_zig = try resolveRemoteDep(allocator, repo_dir, apps, "embed-zig", cfg.dependencies.@"embed-zig");
    errdefer {
        allocator.free(embed_zig.url);
        allocator.free(embed_zig.hash);
    }
    const esp = try resolveRemoteDep(allocator, repo_dir, apps, "esp", cfg.dependencies.esp);
    errdefer {
        allocator.free(esp.url);
        allocator.free(esp.hash);
    }
    const lvgl = try resolveRemoteDep(allocator, repo_dir, apps, "lvgl", cfg.dependencies.lvgl);
    errdefer {
        allocator.free(lvgl.url);
        allocator.free(lvgl.hash);
    }
    const speexdsp = try resolveRemoteDep(allocator, repo_dir, apps, "speexdsp", cfg.dependencies.speexdsp);
    errdefer {
        allocator.free(speexdsp.url);
        allocator.free(speexdsp.hash);
    }
    const opus = try resolveRemoteDep(allocator, repo_dir, apps, "opus", cfg.dependencies.opus);
    errdefer {
        allocator.free(opus.url);
        allocator.free(opus.hash);
    }
    const portaudio = try resolveRemoteDep(allocator, repo_dir, apps, "portaudio", cfg.dependencies.portaudio);
    errdefer {
        allocator.free(portaudio.url);
        allocator.free(portaudio.hash);
    }
    const stb_truetype = try resolveRemoteDep(allocator, repo_dir, apps, "stb-truetype", cfg.dependencies.@"stb-truetype");
    errdefer {
        allocator.free(stb_truetype.url);
        allocator.free(stb_truetype.hash);
    }

    return .{
        .allocator = allocator,
        .embed_zig = embed_zig,
        .esp = esp,
        .lvgl = lvgl,
        .speexdsp = speexdsp,
        .opus = opus,
        .portaudio = portaudio,
        .stb_truetype = stb_truetype,
    };
}

fn resolveRemoteDep(
    allocator: std.mem.Allocator,
    repo_dir: std.fs.Dir,
    apps: []const discover_apps.App,
    dep_name: []const u8,
    spec_str: []const u8,
) !ResolvedRemoteDep {
    const spec = try parseDependencySpec(spec_str);
    const url = try remoteUrlForDependencySpec(allocator, dep_name, spec);
    errdefer allocator.free(url);

    if (try lookupHashForUrlInRepo(allocator, repo_dir, url, apps)) |hash| {
        std.log.info("reusing {s} hash from committed build.zig.zon (url matches package.json)", .{dep_name});
        return .{ .url = url, .hash = hash };
    }
    std.log.info("fetching {s} hash via zig fetch", .{dep_name});
    const hash = try resolveHashFromUrl(allocator, url);
    return .{ .url = url, .hash = hash };
}

const url_needle = ".url = \"";
const hash_needle = ".hash = \"";

/// If any of `build.zig.zon`, `esp/build.zig.zon`, or `desktop/build.zig.zon` contains the exact
/// tarball `url`, returns a copy of the following `.hash` value (avoids redundant `zig fetch`).
pub fn lookupHashForUrlInRepo(
    allocator: std.mem.Allocator,
    repo_dir: std.fs.Dir,
    want_url: []const u8,
    apps: []const discover_apps.App,
) !?[]u8 {
    const manifest_paths = [_][]const u8{
        "build.zig.zon",
        "esp/build.zig.zon",
        "desktop/build.zig.zon",
    };
    for (manifest_paths) |rel| {
        var file = repo_dir.openFile(rel, .{}) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        defer file.close();

        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const bytes = try file.readToEndAlloc(arena.allocator(), 1024 * 1024);

        if (try lookupHashForUrlInBytes(allocator, bytes, want_url)) |h| return h;
    }

    for (apps) |app| {
        const rel_path = try std.fmt.allocPrint(allocator, "{s}/build.zig.zon", .{app.root_path});
        defer allocator.free(rel_path);

        var file = repo_dir.openFile(rel_path, .{}) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        defer file.close();

        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const bytes = try file.readToEndAlloc(arena.allocator(), 1024 * 1024);

        if (try lookupHashForUrlInBytes(allocator, bytes, want_url)) |h| return h;
    }
    return null;
}

fn lookupHashForUrlInBytes(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    want_url: []const u8,
) !?[]u8 {
    var pos: usize = 0;
    while (pos < bytes.len) {
        const u = std.mem.indexOfPos(u8, bytes, pos, url_needle) orelse break;
        const url_start = u + url_needle.len;
        if (url_start >= bytes.len) return null;
        const url_end = std.mem.indexOfScalarPos(u8, bytes, url_start, '"') orelse return null;
        const url = bytes[url_start..url_end];

        const h = std.mem.indexOfPos(u8, bytes, url_end, hash_needle) orelse {
            pos = url_end;
            continue;
        };
        const hash_start = h + hash_needle.len;
        const hash_end = std.mem.indexOfScalarPos(u8, bytes, hash_start, '"') orelse return null;

        if (std.mem.eql(u8, url, want_url)) {
            return try allocator.dupe(u8, bytes[hash_start..hash_end]);
        }
        pos = hash_end;
    }
    return null;
}

pub const DependencySpec = union(enum) {
    file: []const u8,
    github: struct {
        repo: []const u8,
        tag: []const u8,
    },
};

pub fn parseDependencySpec(spec: []const u8) !DependencySpec {
    if (std.mem.startsWith(u8, spec, "file:")) {
        return .{ .file = spec["file:".len..] };
    }
    if (std.mem.startsWith(u8, spec, "github:")) {
        const rest = spec["github:".len..];
        const hash_idx = std.mem.indexOfScalar(u8, rest, '#') orelse return error.InvalidDependencySpec;
        const repo = rest[0..hash_idx];
        const tag = rest[hash_idx + 1 ..];
        if (repo.len == 0 or tag.len == 0) return error.InvalidDependencySpec;
        return .{
            .github = .{
                .repo = repo,
                .tag = tag,
            },
        };
    }
    if (std.mem.indexOfScalar(u8, spec, '#')) |hash_idx| {
        const repo = spec[0..hash_idx];
        const tag = spec[hash_idx + 1 ..];
        if (repo.len == 0 or tag.len == 0) return error.InvalidDependencySpec;
        if (std.mem.indexOfScalar(u8, repo, '/') == null) return error.UnsupportedDependencySpec;
        return .{
            .github = .{
                .repo = repo,
                .tag = tag,
            },
        };
    }
    return error.UnsupportedDependencySpec;
}

pub fn remoteUrlForDependencySpec(
    allocator: std.mem.Allocator,
    dep_name: []const u8,
    spec: DependencySpec,
) ![]u8 {
    switch (spec) {
        .file => return error.DependencyIsLocalPath,
        .github => |github| {
            if (std.mem.eql(u8, dep_name, "esp") and std.mem.eql(u8, github.repo, "embed-zig/esp") and std.mem.eql(u8, github.tag, "v0.1.0")) {
                return std.fmt.allocPrint(
                    allocator,
                    "https://codeload.github.com/embed-zig/esp/tar.gz/{s}",
                    .{"b0bf258479b4edc8f72998b36a30c9b9ba062726"},
                );
            }
            return std.fmt.allocPrint(
                allocator,
                "https://codeload.github.com/{s}/tar.gz/refs/tags/{s}",
                .{ github.repo, github.tag },
            );
        },
    }
}

pub fn localPathForDependencySpec(
    spec: DependencySpec,
) ![]const u8 {
    return switch (spec) {
        .file => |path| path,
        .github => error.DependencyIsRemote,
    };
}

pub fn tagForDependencySpec(spec: DependencySpec) ![]const u8 {
    return switch (spec) {
        .file => error.DependencyIsLocalPath,
        .github => |github| github.tag,
    };
}

pub fn versionForDependencySpec(
    allocator: std.mem.Allocator,
    spec: DependencySpec,
) ![]u8 {
    const tag = try tagForDependencySpec(spec);
    return allocator.dupe(u8, std.mem.trimLeft(u8, tag, "v"));
}
