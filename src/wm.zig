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
    f: x11.Window,
    d: *x11.Display,
    min_size: Size = Size.min(),
    max_size: Size = Size.max(),

    const Geometry = struct {
        pos: Pos,
        size: Size,
    };

    fn init(frame: x11.Window, d: *x11.Display) !Client {
        var c = Client{ .f = frame, .d = d };
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
        if (x11.XGetGeometry(c.d, c.f, &root, &x, &y, &w, &h, &bw, &depth) == 0)
            return error.Error;
        return Geometry{ .pos = Pos.init(x, y), .size = Size.init(w, h) };
    }

    fn updateSizeHints(c: *Client) !void {
        var hints: x11.XSizeHints = undefined;
        var supplied: c_long = undefined;
        if (x11.XGetWMNormalHints(c.d, c.f, &hints, &supplied) != 0) return error.Error;
        c.min_size = Size.init(10, 10);
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
    const WindowOrigin = enum { CreatedBeforeWM, CreatedAfterWM };
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
        var nws: c_uint = 0;
        _ = x11.XQueryTree(m.d, m.root, &root, &parent, &ws, &nws);
        defer _ = x11.XFree(ws);
        std.debug.assert(root == m.root);
        var i: usize = 0;
        while (i < nws) : (i += 1) {
            try m.frameWindow(ws[i], WindowOrigin.CreatedBeforeWM);
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
        } else if (ev.event == m.root) {
            log.trace("ignore UnmapNotify for reparented pre-existing window {}", .{w});
        } else {
            try m.unframeWindow(w);
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
        if (m.clients.get(w)) |client| {
            _ = x11.XConfigureWindow(m.d, client.f, @intCast(c_uint, ev.value_mask), &changes);
            log.info("resize frame {} to ({}, {})", .{ client.f, ev.width, ev.height });
        }
        _ = x11.XConfigureWindow(m.d, w, @intCast(c_uint, ev.value_mask), &changes);
        log.info("resize {} to ({}, {})", .{ w, changes.width, changes.height });
    }

    fn onMapRequest(m: *Manager, ev: x11.XMapRequestEvent) !void {
        log.trace("MapRequest for {}", .{ev.window});
        try m.frameWindow(ev.window, WindowOrigin.CreatedAfterWM);
        _ = x11.XMapWindow(m.d, ev.window);
    }

    fn frameWindow(m: *Manager, w: x11.Window, wo: WindowOrigin) !void {
        if (m.clients.get(w) != null) return error.WindowAlreadyClient;

        const border_width = 3;
        const border_color = 0xff0000;
        const bg_color = 0x0000ff;

        var wattr: x11.XWindowAttributes = undefined;
        if (x11.XGetWindowAttributes(m.d, w, &wattr) == 0) return error.Error;
        if (wo == WindowOrigin.CreatedBeforeWM and ((wattr.override_redirect != 0 or wattr.map_state != x11.IsViewable))) {
            return;
        }

        const frame = x11.XCreateSimpleWindow(
            m.d,
            m.root,
            wattr.x,
            wattr.y,
            @intCast(c_uint, wattr.width),
            @intCast(c_uint, wattr.height),
            border_width,
            border_color,
            bg_color,
        );
        _ = x11.XSelectInput(m.d, frame, x11.SubstructureRedirectMask | x11.SubstructureNotifyMask);
        _ = x11.XAddToSaveSet(m.d, w);
        _ = x11.XReparentWindow(m.d, w, frame, 0, 0);
        _ = x11.XMapWindow(m.d, frame);
        try m.clients.put(w, try Client.init(frame, m.d));

        // move with mod + LB
        _ = x11.XGrabButton(
            m.d,
            x11.Button1,
            modKey,
            w,
            0,
            x11.ButtonPressMask | x11.ButtonReleaseMask | x11.ButtonMotionMask,
            x11.GrabModeAsync,
            x11.GrabModeAsync,
            x11.None,
            x11.None,
        );
        // resize with mod + RB
        _ = x11.XGrabButton(
            m.d,
            x11.Button3,
            modKey,
            w,
            0,
            x11.ButtonPressMask | x11.ButtonReleaseMask | x11.ButtonMotionMask,
            x11.GrabModeAsync,
            x11.GrabModeAsync,
            x11.None,
            x11.None,
        );
        // kill with mod + C
        _ = x11.XGrabKey(
            m.d,
            x11.XKeysymToKeycode(m.d, x11.XK_C),
            modKey,
            w,
            0,
            x11.GrabModeAsync,
            x11.GrabModeAsync,
        );
        // switch windows with mod + Tab
        _ = x11.XGrabKey(
            m.d,
            x11.XKeysymToKeycode(m.d, x11.XK_Tab),
            modKey,
            w,
            0,
            x11.GrabModeAsync,
            x11.GrabModeAsync,
        );
        log.info("framed window {} [{}]", .{ w, frame });
    }

    fn unframeWindow(m: *Manager, w: x11.Window) !void {
        const client = try m.getClient(w);
        const frame = client.f;
        _ = x11.XUnmapWindow(m.d, frame);
        _ = x11.XReparentWindow(m.d, w, m.root, 0, 0);
        _ = x11.XRemoveFromSaveSet(m.d, w);
        _ = x11.XDestroyWindow(m.d, frame);
        _ = m.clients.orderedRemove(w);
        log.info("unframed window {} [{}]", .{ w, frame });
    }

    fn getClient(m: *Manager, w: x11.Window) !Client {
        return m.clients.get(w) orelse return error.WindowIsNotClient;
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
        _ = x11.XRaiseWindow(m.d, client.f);
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
            _ = x11.XMoveWindow(m.d, c.f, frame_pos.x, frame_pos.y);
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
            _ = x11.XResizeWindow(m.d, c.f, w, h);
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

    fn focusNextClient(m: *Manager, w: x11.Window) !void {
        const keys = m.clients.keys();
        var i = for (keys) |cw, i| {
            if (w == cw) break i;
        } else return error.WindowIsNotClient;

        i = (i + 1) % keys.len;
        const nw = keys[i];
        const nc = m.clients.values()[i];
        _ = x11.XRaiseWindow(m.d, nc.f);
        _ = x11.XSetInputFocus(m.d, nw, x11.RevertToPointerRoot, x11.CurrentTime);
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
