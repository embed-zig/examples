const embed = @import("embed");
const lvgl = @import("lvgl");
const testing = @import("testing");
const app_lvgl_osal = @import("app/lvgl_osal.zig");
const lvgl_unit_runner = @import("app/lvgl_unit_runner.zig");

pub fn run(comptime runtime: type) !void {
    const std = runtime.std;
    const app_log = std.log.scoped(.compat_tests);

    comptime {
        app_lvgl_osal.init(runtime);
    }

    try runtime.setup();
    defer runtime.teardown();
    defer if (lvgl.isInitialized()) lvgl.deinit();

    app_log.info("starting lvgl unit runner", .{});

    var runner = testing.T.new(std, .compat_tests);
    defer runner.deinit();

    runner.timeout(240 * std.time.ns_per_s);
    runner.run("lvgl/unit", lvgl_unit_runner.make(std));

    const passed = runner.wait();
    app_log.info("lvgl unit runner finished", .{});
    if (!passed) return error.TestsFailed;
}

test run {
    @import("std").testing.log_level = .info;
    const embed_std = @import("embed_std");

    const HostRuntime = struct {
        pub const std = embed_std.std;
        pub const mem = embed_std.std.mem;
        pub const Thread = embed_std.std.Thread;
        pub const heap = embed_std.std.heap;
        pub const math = embed_std.std.math;
        pub const testing = embed_std.std.testing;
        pub const allocator = @import("std").heap.page_allocator;

        pub fn setup() !void {}
        pub fn teardown() void {}
    };

    try run(HostRuntime);
}
