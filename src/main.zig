const Manager = @import("wm.zig").Manager;
const log = @import("log.zig");

pub fn main() !u8 {
    log.info("starting", .{});

    var wm = Manager{};
    defer wm.deinit();

    const exit_code = try wm.run();

    log.info("exiting with {}", .{exit_code});
    return exit_code;
}
