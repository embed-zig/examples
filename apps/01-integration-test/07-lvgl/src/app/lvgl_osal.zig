const lvgl_osal = @import("lvgl_osal");

pub fn init(comptime runtime: type) void {
    const lvgl_allocator = if (@hasDecl(runtime, "allocator"))
        runtime.allocator
    else
        runtime.testing.allocator;

    _ = lvgl_osal.make(runtime, lvgl_allocator);
}
