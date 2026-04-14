const app = @import("app");
const esp_embed = @import("esp_embed");

const std = esp_embed.std;
const Thread = std.Thread;
const Time = std.time;
const app_log = std.log.scoped(.esp_example);

const EspPlatform = struct {
    pub const std = esp_embed.std;
    pub const mem = esp_embed.std.mem;
    pub const Thread = esp_embed.std.Thread;
    pub const atomic = esp_embed.std.atomic;
    pub const debug = esp_embed.std.debug;
    pub const time = esp_embed.std.time;
    pub const testing = esp_embed.std.testing;
    pub const heap = esp_embed.heap;
    pub const math = esp_embed.std.math;

    pub const allocator = esp_embed.Allocator(.{
        .caps = .spiram_8bit,
    });
    pub const Channel = esp_embed.sync.Channel;
    pub const net = esp_embed.net;
    pub const sync = esp_embed.sync;

    pub fn setup() !void {}
    pub fn teardown() void {}
};

export fn zig_esp_main() callconv(.c) void {
    app.run(EspPlatform) catch |err| {
        app_log.err("app runner failed: {}", .{err});
        @panic("app runner failed");
    };

    while (true) {
        Thread.sleep(10000 * Time.ns_per_ms);
    }
}
