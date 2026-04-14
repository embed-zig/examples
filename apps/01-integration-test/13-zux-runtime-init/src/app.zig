const drivers = @import("drivers");
const zux = @import("zux");

fn makeBuiltApp(comptime lib: type, comptime Channel: fn (type) type) type {
    const AssemblerType = zux.Assembler.make(lib, .{}, Channel);
    var assembler = AssemblerType.init();
    assembler.addSingleButton(.buttons, 7);
    assembler.setState("ui/button", .{.buttons});

    const BuildConfig = assembler.BuildConfig();
    const build_config: BuildConfig = .{
        .buttons = drivers.button.Single,
    };
    return assembler.build(build_config);
}

pub fn run(comptime runtime: type) !void {
    const BuiltApp = comptime makeBuiltApp(runtime.std, runtime.Channel);

    // Smallest known repro: Xtensa LLVM crashes while lowering this init path
    // in optimized builds, even before the value is used at runtime.
    var app = try BuiltApp.init(.{
        .allocator = runtime.allocator,
        .buttons = undefined,
    });
    _ = &app;
}

test "compile_for_host" {
    const embed_std = @import("embed_std");
    _ = comptime makeBuiltApp(embed_std.std, embed_std.sync.Channel);
}
