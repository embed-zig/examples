const stb = @import("stb_truetype");
const testing = @import("testing");

pub fn run(comptime runtime: type) !void {
    const lib = runtime.std;
    const app_log = lib.log.scoped(.compat_tests);

    try runtime.setup();
    defer runtime.teardown();

    app_log.info("starting stb_truetype unit runner", .{});

    var runner = testing.T.new(lib, .compat_tests);
    defer runner.deinit();

    runner.timeout(240 * lib.time.ns_per_s);
    runner.run("stb_truetype/unit", stb.test_runner.unit.make(lib));

    const passed = runner.wait();
    app_log.info("stb_truetype unit runner finished", .{});
    if (!passed) return error.TestsFailed;
}

test run {
    @import("std").testing.log_level = .info;

    const HostRuntime = struct {
        pub const std = @import("std");

        pub fn setup() !void {}
        pub fn teardown() void {}
    };

    try run(HostRuntime);
}
