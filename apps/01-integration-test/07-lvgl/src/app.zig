const glib = @import("glib");
const lvgl = @import("lvgl");
const testing = @import("glib").testing;
const app_lvgl_osal = @import("app/lvgl_osal.zig");

pub fn run(comptime ctx: type, comptime grt: type) !void {
    comptime {
        if (!glib.runtime.is(grt)) @compileError("grt must be a glib runtime namespace");
    }

    const log = grt.std.log.scoped(.compat_tests);

    comptime {
        app_lvgl_osal.init(ctx, grt);
    }

    try ctx.setup();
    defer ctx.teardown();
    defer if (lvgl.isInitialized()) lvgl.deinit();

    log.info("starting lvgl integration runner", .{});

    var testing_display = lvgl.IntegrationTestingDisplay.initPassthrough(ctx.allocator, 320, 240, null);
    defer testing_display.deinit();

    var harness_display = try testing_display.display(grt);
    defer harness_display.deinit();

    var runner = testing.T.new(grt.std, grt.time, .compat_tests);
    defer runner.deinit();

    runner.timeout(480 * glib.time.duration.Second);
    runner.run("lvgl/integration", lvgl.test_runner.integration.make(grt, &harness_display));

    const passed = runner.wait();
    log.info("lvgl integration runner finished", .{});
    if (!passed) return error.TestsFailed;
    try testing_display.assertComplete();
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
