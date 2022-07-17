const std = @import("std");
const x11 = @import("x11.zig");
const log = @import("./log.zig");

const Pos = struct {
    x: i32,
    y: i32,

    fn init(x: anytype, y: anytype) Pos {
        return .{ .x = @intCast(i32, x), .y = @intCast(i32, y) };
    }

    fn minus(p: Pos, p2: Pos) Pos {
        return .{ .x = p.x - p2.x, .y = p.y - p2.y };
    }

    fn plus(p: Pos, p2: Pos) Pos {
        return .{ .x = p.x + p2.x, .y = p.y + p2.y };
    }
};

const Size = struct {
    w: u32,
    h: u32,

    fn init(w: anytype, h: anytype) Size {
        return .{ .w = @intCast(u32, w), .h = @intCast(u32, h) };
    }

    fn min() Size {
        return init(0, 0);
    }

    fn max() Size {
        const maxVal = std.math.maxInt(u32);
        return init(maxVal, maxVal);
    }
};

const Drag = struct {
    start_pos: Pos,
    frame_pos: Pos,
    frame_size: Size,
};

const Client = struct {
    w: x11.Window,
    d: *x11.Display,
    min_size: Size = Size.min(),
    max_size: Size = Size.max(),

    const Geometry = struct {
        pos: Pos,
        size: Size,
    };

    fn init(win: x11.Window, d: *x11.Display) !Client {
        var c = Client{ .w = win, .d = d };
        try c.updateSizeHints();
        return c;
    }

    fn getGeometry(c: Client) !Geometry {
        var root: x11.Window = undefined;
        var x: i32 = undefined;
        var y: i32 = undefined;
        var w: u32 = undefined;
        var h: u32 = undefined;
        var bw: u32 = undefined;
        var depth: u32 = undefined;
        if (x11.XGetGeometry(c.d, c.w, &root, &x, &y, &w, &h, &bw, &depth) == 0)
            return error.Error;
        return Geometry{ .pos = Pos.init(x, y), .size = Size.init(w, h) };
    }

    fn updateSizeHints(c: *Client) !void {
        var hints: *x11.XSizeHints = x11.XAllocSizeHints();
        defer _ = x11.XFree(hints);
        var supplied: c_long = undefined;
        if (x11.XGetWMNormalHints(c.d, c.w, hints, &supplied) == 0) return error.XGetWMNormalHintsFailed;
        c.min_size = Size.init(1, 1);
        c.max_size = Size.max();
        if ((hints.flags & x11.PMinSize != 0) and hints.min_width > 0 and hints.min_height > 0) {
            c.min_size = Size.init(hints.min_width, hints.min_height);
        }
        if (hints.flags & x11.PMaxSize != 0 and hints.max_width > 0 and hints.max_height > 0) {
            c.max_size = Size.init(hints.max_width, hints.max_height);
        }
    }
};

pub const Manager = struct {
    const Clients = std.AutoArrayHashMap(x11.Window, Client);

    d: *x11.Display,
    root: x11.Window,
    focused: ?Client = null,
    clients: Clients = Clients.init(std.heap.c_allocator),
    drag: Drag = undefined,
    wm_delete: x11.Atom = undefined,
    wm_protocols: x11.Atom = undefined,

    pub fn init(_: ?[]u8) !Manager {
        if (isInstanceAlive) return error.WmInstanceAlreadyExists;
        const d = x11.XOpenDisplay(":1") orelse return error.CannotOpenDisplay;
        const r = x11.XDefaultRootWindow(d);
        isInstanceAlive = true;
        return Manager{
            .d = d,
            .root = r,
        };
    }

    pub fn deinit(m: *Manager) void {
        std.debug.assert(isInstanceAlive);
        _ = x11.XCloseDisplay(m.d);
        // TODO deinit clients
        m.clients.deinit();
        isInstanceAlive = false;
        log.info("destroyed wm", .{});
    }

    pub fn run(m: *Manager) !void {
        try m.initWm();
        try m.startEventLoop();
    }

    var isInstanceAlive = false;
    var isWmDetected = false;
    const modKey = x11.Mod1Mask;

    fn initWm(m: *Manager) !void {
        _ = x11.XSetErrorHandler(onWmDetected);
        _ = x11.XSelectInput(m.d, m.root, x11.SubstructureRedirectMask | x11.SubstructureNotifyMask);
        _ = x11.XSync(m.d, 0);
        if (Manager.isWmDetected) return error.AnotherWmDetected;

        _ = x11.XSetErrorHandler(onXError);

        _ = x11.XGrabServer(m.d);
        defer _ = x11.XUngrabServer(m.d);

        var root: x11.Window = undefined;
        var parent: x11.Window = undefined;
        var ws: [*c]x11.Window = undefined;
        var nws: c_uint = undefined;
        _ = x11.XQueryTree(m.d, m.root, &root, &parent, &ws, &nws);
        defer _ = x11.XFree(ws);
        std.debug.assert(root == m.root);
        if (nws > 0) {
            for (ws[0..nws]) |w| {
                var wa: x11.XWindowAttributes = undefined;
                if (x11.XGetWindowAttributes(m.d, w, &wa) == 0) {
                    log.err("XGetWindowAttributes failed for {}", .{w});
                    continue;
                }
                // Only add windows that are visible and don't set override_redirect
                if (wa.override_redirect == 0 and wa.map_state == x11.IsViewable) {
                    _ = m.addClient(w) catch |e| log.err("Add client {} failed with {}", .{ w, e });
                } else {
                    log.info("Ignoring {}", .{w});
                }
            }
            if (m.clients.count() > 0) m.focusClient(m.clients.values()[0]);
        }

        var wa: x11.XSetWindowAttributes = undefined;
        wa.cursor = x11.XCreateFontCursor(m.d, x11.XC_left_ptr);
        _ = x11.XChangeWindowAttributes(m.d, m.root, x11.CWCursor, &wa);

        m.wm_delete = x11.XInternAtom(m.d, "WM_DELETE_WINDOW", 0);
        m.wm_protocols = x11.XInternAtom(m.d, "WM_PROTOCOLS", 0);
        log.info("initialized wm", .{});
    }

    fn startEventLoop(m: *Manager) !void {
        while (true) {
            var e: x11.XEvent = undefined;
            _ = x11.XNextEvent(m.d, &e);
            const ename = x11.eventTypeToString(@intCast(u8, e.type));
            try switch (e.type) {
                x11.CreateNotify => m.onCreateNotify(e.xcreatewindow),
                x11.DestroyNotify => m.onDestroyNotify(e.xdestroywindow),
                x11.ReparentNotify => m.onReparentNotify(e.xreparent),
                x11.MapNotify => m.onMapNotify(e.xmap),
                x11.UnmapNotify => m.onUnmapNotify(e.xunmap),
                x11.ConfigureNotify => {},
                x11.ConfigureRequest => m.onConfigureRequest(e.xconfigurerequest),
                x11.MapRequest => m.onMapRequest(e.xmaprequest),
                x11.ButtonPress => m.onButtonPress(e.xbutton),
                x11.ButtonRelease => m.onButtonRelease(e.xbutton),
                x11.MotionNotify => {
                    while (x11.XCheckTypedWindowEvent(m.d, e.xmotion.window, x11.MotionNotify, &e) != 0) {}
                    try m.onMotionNotify(e.xmotion);
                },
                x11.KeyPress => m.onKeyPress(e.xkey),
                x11.KeyRelease => m.onKeyRelease(e.xkey),
                else => log.trace("ignored event {s}", .{ename}),
            };
        }
    }

    fn onWmDetected(_: ?*x11.Display, err: [*c]x11.XErrorEvent) callconv(.C) c_int {
        const e: *x11.XErrorEvent = err;
        std.debug.assert(e.error_code == x11.BadAccess);
        Manager.isWmDetected = true;
        return 0;
    }

    fn onXError(d: ?*x11.Display, err: [*c]x11.XErrorEvent) callconv(.C) c_int {
        const e: *x11.XErrorEvent = err;
        var error_text: [1024:0]u8 = undefined;
        _ = x11.XGetErrorText(d, e.error_code, @ptrCast([*c]u8, &error_text), @sizeOf(@TypeOf(error_text)));
        log.err("ErrorEvent: request '{s}' xid {x}, error text '{s}'", .{
            x11.requestCodeToString(e.request_code),
            e.resourceid,
            error_text,
        });
        return 0;
    }

    fn onCreateNotify(_: *Manager, ev: x11.XCreateWindowEvent) !void {
        log.trace("CreateNotify for {}", .{ev.window});
    }

    fn onDestroyNotify(_: *Manager, ev: x11.XDestroyWindowEvent) !void {
        log.trace("DestroyNotify for {}", .{ev.window});
    }

    fn onReparentNotify(_: *Manager, ev: x11.XReparentEvent) !void {
        log.trace("ReparentNotify for {} to {}", .{ ev.window, ev.parent });
    }

    fn onMapNotify(_: *Manager, ev: x11.XMapEvent) !void {
        log.trace("MapNotify for {}", .{ev.window});
    }

    fn onUnmapNotify(m: *Manager, ev: x11.XUnmapEvent) !void {
        const w = ev.window;
        log.trace("UnmapNotify for {}", .{w});

        if (m.clients.get(w) == null) {
            log.trace("ignore UnmapNotify for non-client window {}", .{w});
        } else {
            try m.removeClient(w);
        }
    }

    fn onConfigureRequest(m: *Manager, ev: x11.XConfigureRequestEvent) !void {
        log.trace("ConfigureRequest for {}", .{ev.window});
        var changes = x11.XWindowChanges{
            .x = ev.x,
            .y = ev.y,
            .width = ev.width,
            .height = ev.height,
            .border_width = ev.border_width,
            .sibling = ev.above,
            .stack_mode = ev.detail,
        };
        var w = ev.window;
        _ = x11.XConfigureWindow(m.d, w, @intCast(c_uint, ev.value_mask), &changes);
        log.info("resize {} to ({}, {})", .{ w, changes.width, changes.height });
    }

    fn onMapRequest(m: *Manager, ev: x11.XMapRequestEvent) !void {
        log.trace("MapRequest for {}", .{ev.window});
        const c = try m.addClient(ev.window);
        _ = x11.XMapWindow(m.d, ev.window);
        m.focusClient(c);
    }

    const bcf = 0xff8080;
    const bcb = 0x808080;

    fn addClient(m: *Manager, w: x11.Window) !Client {
        if (m.isClient(w)) return error.WindowAlreadyClient;

        var wa: x11.XWindowAttributes = undefined;
        if (x11.XGetWindowAttributes(m.d, w, &wa) == 0) return error.Error;

        const c = try Client.init(w, m.d);
        try m.clients.put(w, c);
        _ = x11.XSelectInput(m.d, w, x11.SubstructureRedirectMask | x11.SubstructureNotifyMask);
        _ = x11.XSetWindowBorderWidth(m.d, w, 3);
        //_ = x11.XAddToSaveSet(m.d, w);

        // move with mod + LB
        _ = x11.XGrabButton(m.d, x11.Button1, modKey, w, 0, x11.ButtonPressMask | x11.ButtonReleaseMask | x11.ButtonMotionMask, x11.GrabModeAsync, x11.GrabModeAsync, x11.None, x11.None);
        // resize with mod + RB
        _ = x11.XGrabButton(m.d, x11.Button3, modKey, w, 0, x11.ButtonPressMask | x11.ButtonReleaseMask | x11.ButtonMotionMask, x11.GrabModeAsync, x11.GrabModeAsync, x11.None, x11.None);
        // kill with mod + C
        _ = x11.XGrabKey(m.d, x11.XKeysymToKeycode(m.d, x11.XK_C), modKey, w, 0, x11.GrabModeAsync, x11.GrabModeAsync);
        // switch windows with mod + Tab
        _ = x11.XGrabKey(m.d, x11.XKeysymToKeycode(m.d, x11.XK_Tab), modKey, w, 0, x11.GrabModeAsync, x11.GrabModeAsync);
        log.info("Added client {}", .{w});
        log.trace("min_size ({}, {}), max_size ({}, {})", .{ c.min_size.w, c.min_size.h, c.max_size.w, c.max_size.h });
        return c;
    }

    fn getClient(m: *Manager, w: x11.Window) !Client {
        return m.clients.get(w) orelse return error.WindowIsNotClient;
    }

    fn isClient(m: *Manager, w: x11.Window) bool {
        return m.clients.contains(w);
    }

    fn removeClient(m: *Manager, w: x11.Window) !void {
        const c = try m.getClient(w);
        //_ = x11.XRemoveFromSaveSet(m.d, w);
        if (m.isClientFocused(c)) m.focused = null;
        std.debug.assert(m.clients.orderedRemove(w));
        if (m.clients.count() > 0) m.focusClient(m.clients.values()[0]);
        log.info("Removed client {}", .{w});
    }

    fn isClientFocused(m: *Manager, c: Client) bool {
        return if (m.focused) |fc| fc.w == c.w else false;
    }

    fn clearFocus(m: *Manager) void {
        if (m.focused) |fc| {
            _ = x11.XSetWindowBorder(m.d, fc.w, bcb);
            _ = x11.XSetInputFocus(m.d, x11.PointerRoot, x11.RevertToPointerRoot, x11.CurrentTime);
            m.focused = null;
            log.info("Unfocused client {}", .{fc.w});
        }
    }

    fn focusClient(m: *Manager, c: Client) void {
        if (m.focused) |fc| {
            if (fc.w == c.w) return;
            m.clearFocus();
        }

        _ = x11.XSetInputFocus(m.d, c.w, x11.RevertToPointerRoot, x11.CurrentTime);
        m.focused = c;
        _ = x11.XSetWindowBorder(m.d, c.w, bcf);
        _ = x11.XRaiseWindow(m.d, c.w);
        log.info("Focused client {}", .{c.w});
    }

    fn onButtonPress(m: *Manager, ev: x11.XButtonEvent) !void {
        log.trace("ButtonPress for {}", .{ev.window});
        const client = try m.getClient(ev.window);
        const g = try client.getGeometry();
        m.drag = Drag{
            .start_pos = Pos.init(ev.x_root, ev.y_root),
            .frame_pos = g.pos,
            .frame_size = g.size,
        };
        _ = x11.XRaiseWindow(m.d, client.w);
    }

    fn onButtonRelease(m: *Manager, ev: x11.XButtonEvent) !void {
        _ = m;
        _ = ev;
    }

    fn onMotionNotify(m: *Manager, ev: x11.XMotionEvent) !void {
        log.trace("MotionNotify for {}", .{ev.window});
        const c = try m.getClient(ev.window);
        const drag_pos = Pos.init(ev.x_root, ev.y_root);
        const delta = drag_pos.minus(m.drag.start_pos);

        if (ev.state & x11.Button1Mask != 0) {
            const frame_pos = m.drag.frame_pos.plus(delta);
            log.info("Moving to ({}, {})", .{ frame_pos.x, frame_pos.y });
            _ = x11.XMoveWindow(m.d, c.w, frame_pos.x, frame_pos.y);
        } else if (ev.state & x11.Button3Mask != 0) {
            var w = @intCast(u32, std.math.max(
                @intCast(i32, c.min_size.w),
                @intCast(i32, m.drag.frame_size.w) + delta.x,
            ));
            var h = @intCast(u32, std.math.max(
                @intCast(i32, c.min_size.h),
                @intCast(i32, m.drag.frame_size.h) + delta.y,
            ));
            w = std.math.min(w, c.max_size.w);
            h = std.math.min(h, c.max_size.h);

            log.info("Resizing to ({}, {})", .{ w, h });
            _ = x11.XResizeWindow(m.d, ev.window, w, h);
        }
    }

    fn sendEvent(m: *Manager, w: x11.Window, protocol: x11.Atom) !void {
        var event = std.mem.zeroes(x11.XEvent);
        event.type = x11.ClientMessage;
        event.xclient.message_type = m.wm_protocols;
        event.xclient.window = w;
        event.xclient.format = 32;
        event.xclient.data.l[0] = @intCast(c_long, protocol);
        if (x11.XSendEvent(m.d, w, 0, x11.NoEventMask, &event) == 0) return error.Error;
    }

    fn killClient(m: *Manager, w: x11.Window) !void {
        var protocols: [*c]x11.Atom = undefined;
        var count: i32 = undefined;
        _ = x11.XGetWMProtocols(m.d, w, &protocols, &count);
        defer _ = x11.XFree(protocols);

        const supports_delete = for (protocols[0..@intCast(usize, count)]) |p| {
            if (p == m.wm_delete) break true;
        } else false;
        if (supports_delete) {
            log.info("Sending wm_delete to {}", .{w});
            try sendEvent(m, w, m.wm_delete);
            return;
        }
        log.info("Killing {}", .{w});
        _ = x11.XKillClient(m.d, w);
    }

    fn focusNextClient(m: *Manager, cw: x11.Window) !void {
        const keys = m.clients.keys();
        var i = for (keys) |k, i| {
            if (k == cw) break i;
        } else return error.WindowIsNotClient;

        i = (i + 1) % keys.len;
        const nc = m.clients.values()[i];
        m.focusClient(nc);
    }

    fn onKeyPress(m: *Manager, ev: x11.XKeyEvent) !void {
        if (ev.state & modKey == 0) return;
        if (ev.keycode == x11.XKeysymToKeycode(m.d, x11.XK_C)) try m.killClient(ev.window);
        if (ev.keycode == x11.XKeysymToKeycode(m.d, x11.XK_Tab)) try m.focusNextClient(ev.window);
    }

    fn onKeyRelease(m: *Manager, ev: x11.XKeyEvent) !void {
        _ = m;
        _ = ev;
    }
};

pub fn main() !void {
    log.info("starting", .{});

    var m = try Manager.init(null);
    defer m.deinit();

    try m.run();

    log.info("exiting", .{});
}
