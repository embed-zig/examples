const std = @import("std");
const esp = @import("esp");

const Module = std.Build.Module;
const BuildContext = esp.idf.BuildContext.BuildContext;

/// Patch per-project configuration imports that the upstream `esp` package
/// cannot close on its own.
pub fn wireProjectConfigImports(
    esp_binding_module: *Module,
    build_config_module: *Module,
    esp_idf_module: *Module,
) void {
    esp_binding_module.addImport("build_config", build_config_module);
    esp_binding_module.addImport("esp_idf", esp_idf_module);
}

pub fn applyEspSysroot(b: *std.Build, build_ctx: BuildContext) void {
    if (build_ctx.toolchain_sysroot) |sysroot| {
        b.sysroot = sysroot.root;
    }
}

pub fn registerAppSteps(b: *std.Build, app: esp.idf.App) void {
    const build_step = b.step("build", "Build the ESP firmware");
    build_step.dependOn(app.combine_binaries);
    build_step.dependOn(app.elf_layout);
    b.default_step = build_step;

    const flash_step = b.step("flash", "Flash the ESP firmware");
    flash_step.dependOn(app.flash);

    const monitor_step = b.step("monitor", "Monitor the ESP serial output without flashing");
    monitor_step.dependOn(app.monitor);
}
