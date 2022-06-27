const wm = @import("wm.zig");
const log = @import("./log.zig");

pub fn main() !void {
    log.info("starting", .{});

    var m = try wm.Manager.init(null);
    defer m.deinit();
    try m.run();

    log.info("exiting", .{});
}
