const std = @import("std");
const portaudio = @import("portaudio");
const testing = @import("testing");

pub fn run(comptime runtime: type) !void {
    const lib = runtime.std;
    const app_log = lib.log.scoped(.compat_tests);

    try runtime.setup();
    defer runtime.teardown();

    app_log.info("starting portaudio unit runner", .{});

    var runner = testing.T.new(lib, .compat_tests);
    defer runner.deinit();

    runner.timeout(240 * lib.time.ns_per_s);
    runner.run("portaudio/unit", testing.TestRunner.fromFn(lib, 128 * 1024, runImpl));

    const passed = runner.wait();
    app_log.info("portaudio unit runner finished", .{});
    if (!passed) return error.TestsFailed;
}

fn runImpl(_: *testing.T, _: std.mem.Allocator) !void {
    try std.testing.expect(@sizeOf(portaudio.DeviceIndex) > 0);
    try std.testing.expect(@sizeOf(portaudio.HostApiIndex) > 0);
    try std.testing.expectEqual(@intFromEnum(portaudio.SampleFormat.int16), @as(c_ulong, 0x00000008));
    try std.testing.expect(@sizeOf(portaudio.PortAudio) > 0);
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
