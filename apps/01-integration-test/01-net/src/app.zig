const glib = @import("glib");
const net = @import("glib").net;
const testing = @import("glib").testing;

pub fn run(comptime ctx: type, comptime grt: type) !void {
    comptime {
        if (!glib.runtime.is(grt)) @compileError("grt must be a glib runtime namespace");
    }

    const log = grt.std.log.scoped(.compat_tests);

    try ctx.setup();
    defer ctx.teardown();

    log.info("starting net integration runner", .{});

    var runner = testing.T.new(grt.std, grt.time, .compat_tests);
    defer runner.deinit();

    runner.timeout(480 * glib.time.duration.Second);
    runner.run("net/integration", net.test_runner.integration.make(grt.std, grt.net));

    const passed = runner.wait();
    log.info("net integration runner finished", .{});
    if (!passed) return error.TestsFailed;
}

test run {
    const std = @import("std");
    const gstd = @import("gstd");

    std.testing.log_level = .info;

    const TestContext = struct {
        pub const allocator = std.testing.allocator;

        pub fn setup() !void {}
        pub fn teardown() void {}
    };
    try run(TestContext, gstd.runtime);
}
