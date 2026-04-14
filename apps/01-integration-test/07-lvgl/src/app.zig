const lvgl = @import("lvgl");
const testing = @import("testing");
const app_lvgl_osal = @import("app/lvgl_osal.zig");

pub fn run(comptime runtime: type) !void {
    const lib = runtime.std;
    const app_log = lib.log.scoped(.compat_tests);
    const alloc = if (@hasDecl(runtime, "allocator")) runtime.allocator else lib.testing.allocator;

    comptime {
        app_lvgl_osal.init(runtime);
    }

    try runtime.setup();
    defer runtime.teardown();
    defer if (lvgl.isInitialized()) lvgl.deinit();

    app_log.info("starting lvgl integration runner", .{});

    var testing_display = lvgl.IntegrationTestingDisplay.initPassthrough(alloc, 320, 240, null);
    defer testing_display.deinit();

    var harness_display = try testing_display.display();
    defer harness_display.deinit();

    var runner = testing.T.new(lib, .compat_tests);
    defer runner.deinit();

    runner.timeout(480 * lib.time.ns_per_s);
    runner.run("lvgl/integration", lvgl.test_runner.integration.make(lib, &harness_display));

    const passed = runner.wait();
    app_log.info("lvgl integration runner finished", .{});
    if (!passed) return error.TestsFailed;
    try testing_display.assertComplete();
}

test run {
    @import("std").testing.log_level = .info;
    const embed_std = @import("embed_std");

    const HostRuntime = struct {
        pub const std = @import("std");
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
