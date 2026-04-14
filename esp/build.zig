const std = @import("std");
const esp = @import("esp");
const config = @import("build/config.zig");
const imports = @import("build/imports.zig");
const wiring = @import("build/wiring.zig");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const app_name = config.resolveAppName(b);
    const build_config_path = config.resolveBuildConfigPath(b);
    const esp_host_dep = b.dependency("esp", .{
        .optimize = optimize,
    });
    const build_config_module = config.createBuildConfigModuleAtPath(
        b,
        build_config_path,
        esp_host_dep.module("esp_idf"),
    );
    const build_ctx = esp.idf.resolveBuildContext(b, .{
        .build_config = build_config_module,
        .esp_dep = esp_host_dep,
    });
    wiring.applyEspSysroot(b, build_ctx);

    const esp_runtime_dep = b.dependency("esp", .{
        .target = build_ctx.target,
        .optimize = optimize,
    });
    const esp_imports = imports.importEspModules(esp_runtime_dep);
    const runtime_build_config_module = config.createBuildConfigModuleAtPath(
        b,
        build_config_path,
        esp_imports.idf,
    );
    wiring.wireProjectConfigImports(
        esp_imports.esp_binding,
        runtime_build_config_module,
        esp_imports.idf,
    );

    const app_dep = b.dependency(app_name, .{
        .target = build_ctx.target,
        .optimize = optimize,
    });
    const app_module = app_dep.module("app");

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/esp_main.zig"),
        .target = build_ctx.target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app", .module = app_module },
            .{ .name = "esp_embed", .module = esp_imports.esp_embed },
        },
    });

    const app = esp.idf.addApp(b, "esp_example", .{
        .context = build_ctx,
        .entry = .{
            .symbol = "zig_esp_main",
            .module = root_module,
        },
    });

    wiring.registerAppSteps(b, app);
}
