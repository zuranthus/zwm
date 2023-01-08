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
    is_passive_input: bool = true,
    base_size: Size = Size.init(0, 0),
    min_size: Size = Size.init(1, 1),
    max_size: Size = Size.init(std.math.maxInt(i32), std.math.maxInt(i32)),
    pos: Pos = Pos.init(0, 0),
    size: Size = Size.init(0, 0),

    pub fn init(win: x11.Window, d: *x11.Display, pos: Pos, inner_size: Size, floating: bool) Client {
        var c = Client{ .w = win, .d = d };
        c.updateWMNormalHints();
        c.updateWMHints();
        c.is_floating = floating or (c.max_size.x != 0 and c.max_size.y != 0 and c.min_size.eq(c.max_size));

        log.trace("Init client {}: pos={}, inner_size={}, floating={}", .{
            c.w,
            pos,
            inner_size,
            c.is_floating,
        });

        c.setFocusedBorder(false);
        _ = x11.XSetWindowBorderWidth(c.d, c.w, c.borderWidth());
        c.moveResize(pos, inner_size.add(2 * c.borderWidth(), 2 * c.borderWidth()));
        return c;
    }

    fn borderWidth(self: *Self) c_uint {
        return if (self.is_fullscreen) 0 else @intCast(c_uint, config.border.width);
    }

    pub fn updateWMHints(self: *Self) void {
        if (@ptrCast(?*x11.XWMHints, x11.XGetWMHints(self.d, self.w))) |hints| {
            defer _ = x11.XFree(hints);

            if (hints.flags & x11.InputHint != 0) self.is_passive_input = hints.input != 0;
            // TODO: urgency hint

            log.trace("WMHints for {}: is_passive_input={}, is_urgent={}", .{
                self.w,
                self.is_passive_input,
                false,
            });
        }
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

    pub fn updateWMNormalHints(self: *Client) void {
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
            // Ensure that max_size >= min_size
            if (self.max_size.lessThan(self.min_size)) {
                self.max_size = self.min_size;
            }

            log.trace("WMNormalHints for {}: min_size={}, max_size={}, base_size={}", .{
                self.w,
                self.min_size,
                self.max_size,
                self.base_size,
            });
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
                const border_size = Size.init(2 * self.borderWidth(), 2 * self.borderWidth());
                final_size = final_size.subVec(border_size).clamp(self.min_size, self.max_size).addVec(border_size);
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
