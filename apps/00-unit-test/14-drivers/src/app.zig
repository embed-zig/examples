const drivers = @import("drivers");
const testing = @import("testing");

pub fn run(comptime runtime: type) !void {
    const std = runtime.std;
    const app_log = std.log.scoped(.compat_tests);

    try runtime.setup();
    defer runtime.teardown();

    app_log.info("starting drivers unit runner", .{});

    var runner = testing.T.new(std, .compat_tests);
    defer runner.deinit();

    runner.timeout(240 * std.time.ns_per_s);
    runner.run("drivers/unit", drivers.test_runner.unit.make(std));

    const passed = runner.wait();
    app_log.info("drivers unit runner finished", .{});
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
