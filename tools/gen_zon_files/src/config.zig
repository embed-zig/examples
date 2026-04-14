const std = @import("std");

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

pub const RemoteHashes = struct {
    allocator: std.mem.Allocator,
    embed_zig: []u8,
    esp: []u8,

    pub fn deinit(self: *RemoteHashes) void {
        self.allocator.free(self.embed_zig);
        self.allocator.free(self.esp);
    }
};

pub fn resolveRemoteHashes(
    allocator: std.mem.Allocator,
    repo_dir: std.fs.Dir,
    cfg: PackageJson,
) !RemoteHashes {
    std.log.info("resolving remote dependency hashes", .{});
    const embed_dep_spec = try parseDependencySpec(cfg.dependencies.@"embed-zig");
    const embed_url = try remoteUrlForDependencySpec(allocator, "embed-zig", embed_dep_spec);
    defer allocator.free(embed_url);

    const esp_dep_spec = try parseDependencySpec(cfg.dependencies.esp);
    const esp_url = try remoteUrlForDependencySpec(allocator, "esp", esp_dep_spec);
    defer allocator.free(esp_url);

    return .{
        .allocator = allocator,
        .embed_zig = try resolveHashFromRepoOrUrl(allocator, repo_dir, .embed_zig, embed_url),
        .esp = try resolveHashFromRepoOrUrl(allocator, repo_dir, .esp, esp_url),
    };
}

const RemoteDepKey = enum {
    embed_zig,
    esp,
};

const RemoteManifest = struct {
    dependencies: Dependencies = .{},

    const Dependencies = struct {
        embed_zig: ?RemoteDependency = null,
        esp: ?RemoteDependency = null,
    };

    const RemoteDependency = struct {
        url: []const u8 = "",
        hash: []const u8 = "",
    };
};

fn resolveHashFromRepoOrUrl(
    allocator: std.mem.Allocator,
    repo_dir: std.fs.Dir,
    dep_key: RemoteDepKey,
    url: []const u8,
) ![]u8 {
    const manifest_paths = [_][]const u8{
        "build.zig.zon",
        "esp/build.zig.zon",
        "desktop/build.zig.zon",
    };
    for (manifest_paths) |manifest_rel_path| {
        if (try lookupHashInManifest(allocator, repo_dir, manifest_rel_path, dep_key, url)) |hash| {
            std.log.info("using cached {s} hash from {s}", .{ @tagName(dep_key), manifest_rel_path });
            return hash;
        }
    }
    std.log.info("fetching {s} hash from {s}", .{ @tagName(dep_key), url });
    return resolveHashFromUrl(allocator, url);
}

fn lookupHashInManifest(
    allocator: std.mem.Allocator,
    repo_dir: std.fs.Dir,
    manifest_rel_path: []const u8,
    dep_key: RemoteDepKey,
    url: []const u8,
) !?[]u8 {
    var file = repo_dir.openFile(manifest_rel_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const bytes = try file.readToEndAlloc(arena_alloc, 1024 * 1024);
    const source = try arena_alloc.dupeZ(u8, bytes);
    const parsed = try std.zon.parse.fromSlice(RemoteManifest, arena_alloc, source, null, .{
        .ignore_unknown_fields = true,
    });

    const maybe_dep = switch (dep_key) {
        .embed_zig => parsed.dependencies.embed_zig,
        .esp => parsed.dependencies.esp,
    };
    const dep = maybe_dep orelse return null;
    if (!std.mem.eql(u8, dep.url, url)) return null;
    if (dep.hash.len == 0) return null;
    return try allocator.dupe(u8, dep.hash);
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
