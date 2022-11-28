const std = @import("std");
const x11 = @import("x11.zig");
const log = @import("log.zig");
const config = @import("config.zig");
const vec = @import("vec.zig");
const Pos = vec.Pos;
const Size = vec.Size;

pub const Client = struct {
    const Self = @This();

    w: x11.Window,
    d: *x11.Display,

    // TODO: replace with ?struct WorkspaceId { monitor: u8, id: u8}, and remove Monitor struct?
    monitor_id: ?u8 = null,
    workspace_id: ?u8 = null,

    is_floating: bool = false,
    is_fullscreen: bool = false,
    min_size: Size = undefined,
    max_size: Size = undefined,

    const Geometry = struct {
        pos: Pos,
        size: Size,
    };


    pub fn init(win: x11.Window, d: *x11.Display, floating: bool, fullscreen: bool) Client {
        var c = Client{ .w = win, .d = d, .is_floating = floating, .is_fullscreen = fullscreen };
        c.setFocusedBorder(false);
        _ = x11.XSetWindowBorderWidth(c.d, c.w, config.border.width);
        c.updateSizeHints();
        return c;
    }

    pub fn getGeometry(self: *Client) !Geometry {
        var root: x11.Window = undefined;
        var x: i32 = 0;
        var y: i32 = 0;
        var w: u32 = 0;
        var h: u32 = 0;
        var bw: u32 = 0;
        var depth: u32 = 0;
        if (x11.XGetGeometry(self.d, self.w, &root, &x, &y, &w, &h, &bw, &depth) == 0)
            return error.Error;
        return Geometry{ .pos = Pos.init(x, y), .size = Size.init(w, h) };
    }

    pub fn updateSizeHints(self: *Client) void {
        self.min_size = Size.init(1, 1);
        self.max_size = Size.init(100000, 100000);
        var hints: *x11.XSizeHints = x11.XAllocSizeHints();
        defer _ = x11.XFree(hints);
        var supplied: c_long = undefined;
        if (x11.XGetWMNormalHints(self.d, self.w, hints, &supplied) == 0) return;
        if ((hints.flags & x11.PMinSize != 0) and hints.min_width > 0 and hints.min_height > 0) {
            self.min_size = Size.init(hints.min_width, hints.min_height);
        }
        if (hints.flags & x11.PMaxSize != 0 and hints.max_width > 0 and hints.max_height > 0) {
            self.max_size = Size.init(hints.max_width, hints.max_height);
        }
    }

    pub fn setFocusedBorder(self: *Client, focused: bool) void {
        const border_color: c_ulong = if (focused) config.border.color_focused else config.border.color_normal;
        _ = x11.XSetWindowBorder(self.d, self.w, border_color);
    }

    pub fn move(self: *Client, p: Pos) void {
        _ = x11.XMoveWindow(self.d, self.w, p.x, p.y);
        log.trace("move {} to ({}, {})", .{ self.w, p.x, p.y });
    }

    pub fn resize(self: *Client, sz: Size) void {
        const border_width = config.border.width;
        const new_size = sz.clamp(self.min_size, self.max_size).sub(Size.init(2 * border_width, 2 * border_width));
        _ = x11.XResizeWindow(self.d, self.w, new_size.w, new_size.h);
        log.trace("resize {} to ({}, {})", .{ self.w, new_size.w, new_size.h });
    }

    pub fn moveResize(self: *Client, pos: Pos, size: Size) void {
        const border_width = config.border.width;
        const w = @intCast(u32, std.math.clamp(size.x, self.min_size.x, self.max_size.x) - 2 * border_width);
        const h = @intCast(u32, std.math.clamp(size.y, self.min_size.y, self.max_size.y) - 2 * border_width);
        _ = x11.XMoveResizeWindow(self.d, self.w, pos.x, pos.y, w, h);
        log.trace("move-resize {} to ({}, {}), ({}, {})", .{ self.w, pos.x, pos.y, w, h });
    }
};
