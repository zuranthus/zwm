const std = @import("std");
const log = @import("log.zig");
const xlib = @import("x11.zig");

pub fn manageExistingWindows(display: *xlib.Display, root: xlib.Window) void {
    var unused_win: xlib.Window = undefined;
    var windows: [*c]xlib.Window = null;
    var num: c_uint = 0;
    _ = xlib.XQueryTree(display, root, &unused_win, &unused_win, &windows, &num);
    defer _ = if (windows != null) xlib.XFree(windows);
    if (num == 0) return;

    // Manage non-transient windows first
    for (windows[0..num]) |win| {
        if (xlib.XGetTransientForHint(display, win, &unused_win) == 0)
            manageWindow(display, win) catch |err| {
                log.err("Failed to manage window {}: {}", .{ win, err });
            };
    }
    // Then manage transient windows
    for (windows[0..num]) |win| {
        if (xlib.XGetTransientForHint(display, win, &unused_win) != 0)
            manageWindow(display, win) catch |err| {
                log.err("Failed to manage window {}: {}", .{ win, err });
            };
    }

    // // Manage transient windows
    // for (windows[0..num]) |w| {
    //     var wa = std.mem.zeroes(xlib.XWindowAttributes);
    //     if (xlib.XGetWindowAttributes(display, w, &wa) == 0) {
    //         log.err("XGetWindowAttributes failed for {}", .{w});
    //         continue;
    //     }
    //     if (xlib.XGetTransientForHint(display, w, &unused_win) == 0)
    //         continue;

    //     // Only add windows that are visible or in iconic state
    //     if (wa.map_state == xlib.IsViewable or xlib.getWindowWMState(display, w) == xlib.IconicState) {
    //         manageWindow(display, w);
    //     } else {
    //         log.info("Ignoring hidden transient {}", .{w});
    //     }
    // }
}

pub fn manageWindow(display: *xlib.Display, win: xlib.Window) !void {
    var wa = std.mem.zeroes(xlib.XWindowAttributes);
    if (xlib.XGetWindowAttributes(display, win, &wa) == 0)
        return error.XGetWindowAttributesFailed;

    // Don't manage override redirect windows
    if (wa.override_redirect != 0) return;
}
