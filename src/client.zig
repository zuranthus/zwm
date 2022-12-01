const std = @import("std");
const x11 = @import("x11.zig");
const log = @import("log.zig");
const config = @import("config.zig");
const atoms = @import("atoms.zig");
const util = @import("util.zig");
const Pos = util.Pos;
const Size = util.Size;

pub const Client = struct {
    const Self = @This();

    w: x11.Window,
    d: *x11.Display,

    // TODO: replace with ?struct WorkspaceId { monitor: u8, id: u8}, and remove Monitor struct?
    monitor_id: ?u8 = null,
    workspace_id: ?u8 = null,

    is_floating: bool = false,
    is_fullscreen: bool = false,
    is_focused_border: bool = false,
    base_size: Size = Size.init(0, 0),
    min_size: Size = Size.init(0, 0),
    max_size: Size = Size.init(std.math.maxInt(i32), std.math.maxInt(i32)),
    pos: Pos,
    size: Size,

    pub fn init(win: x11.Window, d: *x11.Display, pos: Pos, size: Size, floating: bool) Client {
        var c = Client{ .w = win, .d = d, .pos = pos, .size = size, .is_floating = floating };
        c.setFocusedBorder(false);
        _ = x11.XSetWindowBorderWidth(c.d, c.w, c.borderWidth());
        c.updateSizeHints();
        if (c.max_size.x != 0 and c.max_size.y != 0 and c.min_size.eq(c.max_size)) c.is_floating = true;
        c.moveResize(pos, size);
        return c;
    }

    fn borderWidth(self: *Self) c_uint {
        return if (self.is_fullscreen) 0 else @intCast(c_uint, config.border.width);
    }

    pub fn setFullscreenState(self: *Self, is_fullscreen: bool) void {
        if (self.is_fullscreen == is_fullscreen) return;

        self.is_fullscreen = is_fullscreen;
        _ = x11.XSetWindowBorderWidth(self.d, self.w, self.borderWidth());
        self.setFocusedBorder(self.is_focused_border);
        x11.setWindowProperty(
            self.d,
            self.w,
            atoms.net_wm_state,
            x11.XA_ATOM,
            if (is_fullscreen) atoms.net_wm_state_fullscreen else 0,
        );
    }

    pub fn updateSizeHints(self: *Client) void {
        var hints: x11.XSizeHints = undefined;
        var unused: c_long = undefined;
        if (x11.XGetWMNormalHints(self.d, self.w, &hints, &unused) != 0) {
            if (hints.flags & x11.PMinSize != 0) self.min_size = Size.init(hints.min_width, hints.min_height);
            if (hints.flags & x11.PMaxSize != 0) self.max_size = Size.init(hints.max_width, hints.max_height);
            if (hints.flags & x11.PBaseSize != 0) {
                self.base_size = Size.init(hints.base_width, hints.base_height);
            } else {
                self.base_size = self.min_size;
            }
        }
    }

    pub fn setFocusedBorder(self: *Client, focused: bool) void {
        // TODO: border color doesn't work for fullscreen
        self.is_focused_border = focused;
        const border_color: c_ulong = if (focused) config.border.color_focused else config.border.color_normal;
        _ = x11.XSetWindowBorder(self.d, self.w, border_color);
    }

    pub fn move(self: *Client, p: Pos) void {
        if (!self.is_fullscreen) self.pos = p;
        _ = x11.XMoveWindow(self.d, self.w, p.x, p.y);
        log.trace("move {} to ({}, {})", .{ self.w, p.x, p.y });
    }

    pub fn resize(self: *Client, size: Size) void {
        var final_size = size;
        if (!self.is_fullscreen) {
            // Apply size constraints and store size only if the client is not fullscreen.
            // Fullscreen clients just change the size directly.
            if (self.is_floating) {
                final_size = Size.init(
                    std.math.clamp(final_size.x, self.min_size.x, self.max_size.x),
                    std.math.clamp(final_size.y, self.min_size.y, self.max_size.y),
                );
            }
            self.size = final_size;
        }
        log.trace("resize {} to ({}, {})", .{ self.w, final_size.x, final_size.y });

        final_size = final_size.sub(2 * self.borderWidth(), 2 * self.borderWidth());
        _ = x11.XResizeWindow(self.d, self.w, @intCast(c_uint, final_size.x), @intCast(c_uint, final_size.y));
    }

    pub fn moveResize(self: *Client, pos: Pos, size: Size) void {
        // TODO: minimize the number of xlib calls
        self.move(pos);
        self.resize(size);
    }
};
