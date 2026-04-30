const glib = @import("glib");
const portaudio = @import("portaudio");
const testing = @import("glib").testing;

pub fn run(comptime ctx: type, comptime grt: type) !void {
    comptime {
        if (!glib.runtime.is(grt)) @compileError("grt must be a glib runtime namespace");
    }

    const log = grt.std.log.scoped(.compat_tests);

    try ctx.setup();
    defer ctx.teardown();

    log.info("starting portaudio unit runner", .{});

    var runner = testing.T.new(grt.std, grt.time, .compat_tests);
    defer runner.deinit();

    const PortAudioUnit = struct {
        fn runImpl(_: *testing.T, _: grt.std.mem.Allocator) !void {
            try grt.std.testing.expect(@sizeOf(portaudio.DeviceIndex) > 0);
            try grt.std.testing.expect(@sizeOf(portaudio.HostApiIndex) > 0);
            try grt.std.testing.expectEqual(@intFromEnum(portaudio.SampleFormat.int16), @as(c_ulong, 0x00000008));
            try grt.std.testing.expect(@sizeOf(portaudio.PortAudio) > 0);
        }
    };

    runner.timeout(240 * glib.time.duration.Second);
    runner.run("portaudio/unit", testing.TestRunner.fromFn(grt.std, 128 * 1024, PortAudioUnit.runImpl));

    const passed = runner.wait();
    log.info("portaudio unit runner finished", .{});
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
