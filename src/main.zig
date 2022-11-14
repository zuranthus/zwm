const std = @import("std");
const log = @import("log.zig");
const Manager = @import("wm.zig").Manager;

pub fn main() !u8 {
    log.info("starting", .{});

    // quick-n-dirty args parse
    var stateFile: ?[]const u8 = null;
    var display: ?[:0]const u8 = null;
    var it = try std.process.argsWithAllocator(std.heap.c_allocator);
    defer it.deinit();
    _ = it.skip(); // skip prog name
    while (it.next()) |arg| {
        if (std.mem.eql(u8, "--save-state", arg)) {
            stateFile = it.next();
        } else if (std.mem.eql(u8, "--display", arg)) {
            display = it.next();
        }
    }

    var wm = Manager{};
    defer wm.deinit();

    const exit_code = try wm.run(display, stateFile);

    log.info("exiting with {}", .{exit_code});
    return exit_code;
}
