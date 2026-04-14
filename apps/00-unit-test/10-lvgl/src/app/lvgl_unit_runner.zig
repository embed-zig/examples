const embed = @import("embed");
const lvgl = @import("lvgl");
const testing = @import("testing");
const TestingDisplay = @import("lvgl_test_utils/TestingDisplay.zig");

pub fn make(comptime lib: type) testing.TestRunner {
    const Runner = struct {
        pub fn init(self: *@This(), allocator: embed.mem.Allocator) !void {
            _ = self;
            _ = allocator;
        }

        pub fn run(self: *@This(), t: *testing.T, allocator: embed.mem.Allocator) bool {
            _ = self;
            _ = allocator;

            t.run("binding", lvgl.binding.TestRunner(lib));
            t.run("types", lvgl.types.TestRunner(lib));
            t.run("Color", lvgl.Color.TestRunner(lib));
            t.run("Point", lvgl.Point.TestRunner(lib));
            t.run("Area", lvgl.Area.TestRunner(lib));
            t.run("Style", lvgl.Style.TestRunner(lib));
            t.run("Display", lvgl.Display.TestRunner(lib));
            t.run("Indev", lvgl.Indev.TestRunner(lib));
            t.run("Tick", lvgl.Tick.TestRunner(lib));
            t.run("Event", lvgl.Event.TestRunner(lib));
            t.run("Anim", lvgl.Anim.TestRunner(lib));
            t.run("Subject", lvgl.Subject.TestRunner(lib));
            t.run("Observer", lvgl.Observer.TestRunner(lib));
            t.run("object/Obj", lvgl.object.Obj.TestRunner(lib));
            t.run("object/Tree", lvgl.object.Tree.TestRunner(lib));
            t.run("object/Flags", lvgl.object.Flags.TestRunner(lib));
            t.run("object/State", lvgl.object.State.TestRunner(lib));
            t.run("widget/Label", lvgl.Label.TestRunner(lib));
            t.run("widget/Button", lvgl.Button.TestRunner(lib));
            t.run("display/TestingDisplay", TestingDisplay.TestRunner(lib));

            return t.wait();
        }

        pub fn deinit(self: *@This(), allocator: embed.mem.Allocator) void {
            _ = allocator;
            lib.testing.allocator.destroy(self);
        }
    };

    const runner = lib.testing.allocator.create(Runner) catch @panic("OOM");
    runner.* = .{};
    return testing.TestRunner.make(Runner).new(runner);
}
