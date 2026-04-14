const std = @import("std");
const esp = @import("esp");

const Module = std.Build.Module;

pub const EspImports = struct {
    idf: *Module,
    esp_embed: *Module,
    esp_binding: *Module,
};

pub fn importEspModules(esp_dep: *std.Build.Dependency) EspImports {
    return .{
        .idf = esp_dep.module("esp_idf"),
        .esp_embed = esp_dep.module("esp_embed"),
        .esp_binding = esp_dep.module("esp_binding"),
    };
}
