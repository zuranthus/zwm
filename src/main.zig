const wm = @import("wm.zig");
const log = @import("./log.zig");

pub fn main() !void {
    log.info("starting", .{});

    var m = wm.Manager{};
    try m.init();
    defer m.deinit();

    try m.run();

    log.info("exiting", .{});
}
