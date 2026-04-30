const embed = @import("embed");
const glib = @import("glib");
const lvgl = @import("lvgl");
const testing = @import("glib").testing;
const app_lvgl_osal = @import("app/lvgl_osal.zig");
const lvgl_unit_runner = @import("app/lvgl_unit_runner.zig");

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

    log.info("starting lvgl unit runner", .{});

    var runner = testing.T.new(grt.std, grt.time, .compat_tests);
    defer runner.deinit();

    runner.timeout(240 * glib.time.duration.Second);
    runner.run("lvgl/unit", lvgl_unit_runner.make(grt));

    const passed = runner.wait();
    log.info("lvgl unit runner finished", .{});
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
