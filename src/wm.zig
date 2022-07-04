const std = @import("std");
const x11 = @import("x11.zig");
const log = @import("./log.zig");

pub const Manager = struct {
    d: *x11.Display,
    root: x11.Window,
    clients: std.AutoHashMap(x11.Window, x11.Window),

    pub fn init(_: ?[]u8) !Manager {
        if (isInstanceAlive) return error.WmInstanceAlreadyExists;
        const d = x11.XOpenDisplay(":1") orelse return error.CannotOpenDisplay;
        const r = x11.XDefaultRootWindow(d);
        const clients = std.AutoHashMap(x11.Window, x11.Window).init(std.heap.c_allocator);
        isInstanceAlive = true;
        return Manager{
            .d = d,
            .root = r,
            .clients = clients,
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
    const modKey = x11.Mod4Mask;

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
        if (m.clients.get(w)) |frame| {
            _ = x11.XConfigureWindow(m.d, frame, @intCast(c_uint, ev.value_mask), &changes);
            log.info("resize frame {} to ({}, {})", .{ frame, ev.width, ev.height });
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
        try m.clients.put(w, frame);

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
        const frame = m.clients.get(w) orelse return error.WindowIsNotClient;
        _ = x11.XUnmapWindow(m.d, frame);
        _ = x11.XReparentWindow(m.d, w, m.root, 0, 0);
        _ = x11.XRemoveFromSaveSet(m.d, w);
        _ = x11.XDestroyWindow(m.d, frame);
        _ = m.clients.remove(w);
        log.info("unframed window {} [{}]", .{ w, frame });
    }

    fn onButtonPress(m: *Manager, ev: x11.XButtonEvent) !void {
        _ = m;
        _ = ev;
    }

    fn onButtonRelease(m: *Manager, ev: x11.XButtonEvent) !void {
        _ = m;
        _ = ev;
    }

    fn onMotionNotify(m: *Manager, ev: x11.XMotionEvent) !void {
        _ = m;
        _ = ev;
    }

    fn onKeyPress(m: *Manager, ev: x11.XKeyEvent) !void {
        _ = m;
        _ = ev;
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
