const std = @import("std");

const forwarded_modules = [_][]const u8{
    "glib",
    "gstd",
    "embed",
    "core_bluetooth",
    "core_wlan",
    "lvgl",
    "lvgl_osal",
    "mbedtls",
    "opus",
    "portaudio",
    "speexdsp",
    "stb_truetype",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const upstream = b.dependency("upstream", .{
        .target = target,
        .optimize = optimize,
    });

    for (forwarded_modules) |module_name| {
        b.modules.put(b.dupe(module_name), upstream.module(module_name)) catch @panic("OOM");
    }
}
