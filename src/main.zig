const Manager = @import("wm.zig").Manager;
const log = @import("log.zig");

pub fn main() !void {
    log.info("starting", .{});

    var wm = Manager{};
    defer wm.deinit();

    try wm.run();

    log.info("exiting", .{});
}
