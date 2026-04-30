const std = @import("std");
const lvgl = @import("lvgl");
const testing = @import("glib").testing;
const TestingDisplay = @import("lvgl_test_utils/TestingDisplay.zig");

pub fn make(comptime grt: type) testing.TestRunner {
    const Runner = struct {
        pub fn init(self: *@This(), allocator: std.mem.Allocator) !void {
            _ = self;
            _ = allocator;
        }

        pub fn run(self: *@This(), t: *testing.T, allocator: std.mem.Allocator) bool {
            _ = self;
            _ = allocator;

            t.run("binding", lvgl.binding.TestRunner(grt));
            t.run("types", lvgl.types.TestRunner(grt));
            t.run("Color", lvgl.Color.TestRunner(grt));
            t.run("Point", lvgl.Point.TestRunner(grt));
            t.run("Area", lvgl.Area.TestRunner(grt));
            t.run("Style", lvgl.Style.TestRunner(grt));
            t.run("Display", lvgl.Display.TestRunner(grt));
            t.run("Indev", lvgl.Indev.TestRunner(grt));
            t.run("Tick", lvgl.Tick.TestRunner(grt));
            t.run("Event", lvgl.Event.TestRunner(grt));
            t.run("Anim", lvgl.Anim.TestRunner(grt));
            t.run("Subject", lvgl.Subject.TestRunner(grt));
            t.run("Observer", lvgl.Observer.TestRunner(grt));
            t.run("object/Obj", lvgl.object.Obj.TestRunner(grt));
            t.run("object/Tree", lvgl.object.Tree.TestRunner(grt));
            t.run("object/Flags", lvgl.object.Flags.TestRunner(grt));
            t.run("object/State", lvgl.object.State.TestRunner(grt));
            t.run("widget/Label", lvgl.Label.TestRunner(grt));
            t.run("widget/Button", lvgl.Button.TestRunner(grt));
            t.run("display/TestingDisplay", TestingDisplay.TestRunner(grt));

            return t.wait();
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            _ = allocator;
            std.heap.page_allocator.destroy(self);
        }
    };

    const runner = std.heap.page_allocator.create(Runner) catch @panic("OOM");
    runner.* = .{};
    return testing.TestRunner.make(Runner).new(runner);
}
