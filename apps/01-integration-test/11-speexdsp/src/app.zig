const speexdsp = @import("speexdsp");
const testing = @import("testing");

pub fn run(comptime runtime: type) !void {
    const lib = runtime.std;
    const app_log = lib.log.scoped(.compat_tests);

    try runtime.setup();
    defer runtime.teardown();

    app_log.info("starting speexdsp integration runner", .{});

    var runner = testing.T.new(lib, .compat_tests);
    defer runner.deinit();

    runner.timeout(480 * lib.time.ns_per_s);
    runner.run("speexdsp/integration", speexdsp.test_runner.integration.make(lib));

    const passed = runner.wait();
    app_log.info("speexdsp integration runner finished", .{});
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
