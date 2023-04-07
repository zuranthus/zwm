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

const Rect = struct {
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,
};

const Location = struct {
    monitor_id: u8 = 0,
    workspace_id: u8 = 0,
};

var clients: ?*Client = null;
var focus: struct {
    location: Location = .{},
    client: ?*Client = null,
} = .{};
var dock: ?*Client = null;

const Client = struct {
    // window properties
    window: xlib.Window,
    transient_for: ?xlib.Window = null,
    accepts_focus: bool = false,
    size_hints: struct {
        base_width: i32 = 0,
        base_height: i32 = 0,
        min_width: i32 = 0,
        min_height: i32 = 0,
        max_width: i32 = 0,
        max_height: i32 = 0,
    } = .{},
    protocols: packed struct {
        wm_take_focus: bool = false,
        wm_delete_window: bool = false,
    } = .{},

    // client state
    location: Location = .{},
    state: packed struct {
        floating: bool = false,
        fullscreen: bool = false,
        urgent: bool = false,
    } = .{},
    rect: Rect = .{},

    // order and focus stacks
    next_order: ?*Client = null,
    next_focus: ?*Client = null,
};

fn clientByWindow(_: xlib.Window) ?*Client {
    return null;
}

pub fn manageWindow(display: *xlib.Display, win: xlib.Window) !void {
    var wa = std.mem.zeroes(xlib.XWindowAttributes);
    if (xlib.XGetWindowAttributes(display, win, &wa) == 0)
        return error.XGetWindowAttributesFailed;

    // Don't manage override redirect windows
    if (wa.override_redirect != 0) return;
    // Don't manage windows that are already managed
    if (clientByWindow(win) != null) return;
}
