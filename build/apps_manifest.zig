const std = @import("std");

pub const App = struct {
    key: []const u8,
    group: []const u8,
    root_path: []const u8,
};

pub const Manifest = struct {
    apps: []App,
};

pub const Loaded = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,
    parsed: std.json.Parsed(Manifest),

    pub fn deinit(self: *Loaded) void {
        self.parsed.deinit();
        self.allocator.free(self.bytes);
    }
};

pub fn loadFromAbsolutePath(allocator: std.mem.Allocator, path: []const u8) !Loaded {
    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    const bytes = try file.readToEndAlloc(allocator, 8 * 1024 * 1024);
    errdefer allocator.free(bytes);

    const parsed = try std.json.parseFromSlice(Manifest, allocator, bytes, .{
        .allocate = .alloc_always,
    });
    errdefer parsed.deinit();

    return .{
        .allocator = allocator,
        .bytes = bytes,
        .parsed = parsed,
    };
}
