const esp_idf = @import("esp_idf");

pub const board = .{
    .name = @as([]const u8, "board.esp32s3_devkit"),
    .chip = @as([]const u8, "esp32s3"),
    .target_arch = @as([]const u8, "xtensa"),
    .target_arch_config_flag = @as([]const u8, "CONFIG_IDF_TARGET_ARCH_XTENSA"),
    .target_config_flag = @as([]const u8, "CONFIG_IDF_TARGET_ESP32S3"),
};

pub const partition_table = esp_idf.PartitionTable.make(.{
    .entries = &.{
        .{ .name = "nvs", .kind = .data, .subtype = .nvs, .size = 0x6000 },
        .{ .name = "phy_init", .kind = .data, .subtype = .phy, .size = 0x1000 },
        .{ .name = "factory", .kind = .app, .subtype = .factory, .size = 0x600000 },
    },
});

pub const config = esp_idf.SdkConfig.make(.{
    .esptool_py = .{
        .esptoolpy_flashsize = "16MB",
        .esptoolpy_flashsize_16mb = true,
        .esptoolpy_flashsize_2mb = false,
    },
    .esp_system = .{
        .esp_default_cpu_freq_mhz = 240,
        .esp_default_cpu_freq_mhz_80 = false,
        .esp_default_cpu_freq_mhz_160 = false,
        .esp_default_cpu_freq_mhz_240 = true,
    },
    .esp_psram = .{
        .spiram = true,
        .spiram_mode_quad = false,
        .spiram_mode_oct = true,
        .spiram_speed_80m = true,
        .spiram_speed_40m = false,
        .spiram_speed_120m = false,
    },
});
