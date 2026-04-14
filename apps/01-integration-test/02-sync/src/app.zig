const sync = @import("sync");
const testing = @import("testing");

pub fn run(comptime runtime: type) !void {
    const std = runtime.std;
    const app_log = std.log.scoped(.compat_tests);

    try runtime.setup();
    defer runtime.teardown();

    app_log.info("starting sync integration runner", .{});

    var runner = testing.T.new(std, .compat_tests);
    defer runner.deinit();

    runner.timeout(480 * std.time.ns_per_s);
    runner.run("sync/integration", sync.test_runner.integration.make(std, runtime.Channel));

    const passed = runner.wait();
    app_log.info("sync integration runner finished", .{});
    if (!passed) return error.TestsFailed;
}

test run {
    @import("std").testing.log_level = .info;
    const embed_std = @import("embed_std");

    const HostRuntime = struct {
        pub const std = @import("std");
        pub const Channel = embed_std.sync.Channel;

        pub fn setup() !void {}
        pub fn teardown() void {}
    };

    try run(HostRuntime);
}
