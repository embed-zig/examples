const glib = @import("glib");
const drivers = @import("embed").drivers;
const zux = @import("embed").zux;

fn makeBuiltApp(comptime grt: type) type {
    const AssemblerType = zux.assemble(grt, .{});
    var assembler = AssemblerType.init();
    assembler.addSingleButton(.buttons, 7);
    assembler.setState("ui/button", .{.buttons});

    const BuildConfig = assembler.BuildConfig();
    const build_config: BuildConfig = .{
        .buttons = drivers.button.Single,
    };
    return assembler.build(build_config);
}

pub fn run(comptime ctx: type, comptime grt: type) !void {
    comptime {
        if (!glib.runtime.is(grt)) @compileError("grt must be a glib runtime namespace");
    }

    const BuiltApp = comptime makeBuiltApp(grt);

    try ctx.setup();
    defer ctx.teardown();

    // Smallest known repro: Xtensa LLVM crashes while lowering this init path
    // in optimized builds, even before the value is used at runtime.
    var app = try BuiltApp.init(.{
        .allocator = ctx.allocator,
        .buttons = undefined,
    });
    _ = &app;
}

test "compile_for_host" {
    const gstd = @import("gstd");

    _ = comptime makeBuiltApp(gstd.runtime);
}
