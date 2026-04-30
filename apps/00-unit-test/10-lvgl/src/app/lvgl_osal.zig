const lvgl_osal = @import("lvgl_osal");

pub fn init(comptime ctx: type, comptime grt: type) void {
    _ = lvgl_osal.make(grt, ctx.allocator);
}
