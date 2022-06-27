const std = @import("std");
const c = @import("x11.zig");
const util = @import("util.zig");
const log = @import("./log.zig");

const ZwmErrors = error{
    Error,
    OtherWMRunning,
};

const Manager = struct {
    d: *c.Display,
    r: c.Window,
    clients: std.AutoHashMap(c.Window, c.Window),

    var ce: ?ZwmErrors = null;

    const WindowOrigin = enum { CreatedBeforeWM, CreatedAfterWM };

    pub fn init(display: ?[]u8) !Manager {
        _ = display;
        const d = c.XOpenDisplay(":1") orelse return ZwmErrors.Error;
        const r = c.XDefaultRootWindow(d);
        return Manager{
            .d = d,
            .r = r,
            .clients = std.AutoHashMap(c.Window, c.Window).init(std.heap.c_allocator),
        };
    }

    pub fn deinit(m: *Manager) void {
        _ = c.XCloseDisplay(m.d);
        // TODO deinit clients
        m.clients.deinit();
        log.info("destroyed wm\n", .{});
    }

    fn _InitWm(m: *Manager) !void {
        _ = c.XSetErrorHandler(on_wmdetected);
        _ = c.XSelectInput(m.d, m.r, c.SubstructureRedirectMask | c.SubstructureNotifyMask);
        _ = c.XSync(m.d, 0);
        if (Manager.ce) |err| return err;

        _ = c.XSetErrorHandler(on_xerror);

        _ = c.XGrabServer(m.d);
        defer _ = c.XUngrabServer(m.d);

        var root: c.Window = undefined;
        var parent: c.Window = undefined;
        var ws: [*c]c.Window = undefined;
        var nws: c_uint = 0;
        _ = c.XQueryTree(m.d, m.r, &root, &parent, &ws, &nws);
        defer _ = c.XFree(ws);
        std.debug.assert(root == m.r);

        var i: usize = 0;
        while (i < nws) : (i += 1) {
            try m.frameWindow(ws[i], WindowOrigin.CreatedBeforeWM);
        }
        log.info("initialized wm\n", .{});
    }

    fn _EventLoop(m: *Manager) !void {
        while (true) {
            var e: c.XEvent = undefined;
            _ = c.XNextEvent(m.d, &e);
            const ename = util.xEventTypeToString(@intCast(u8, e.type));
            log.trace("received event {s}\n", .{ename});
            try switch (e.type) {
                c.CreateNotify => m._OnCreateNotify(e.xcreatewindow),
                c.DestroyNotify => m._OnDestroyNotify(e.xdestroywindow),
                c.ReparentNotify => m._OnReparentNotify(e.xreparent),
                c.MapNotify => m._OnMapNotify(e.xmap),
                c.UnmapNotify => m._OnUnmapNotify(e.xunmap),
                c.ConfigureRequest => m._OnConfigureRequest(e.xconfigurerequest),
                c.MapRequest => m._OnMapRequest(e.xmaprequest),
                else => log.trace("ignored event {s}\n", .{ename}),
            };
        }
    }

    fn _OnCreateNotify(_: *Manager, ev: c.XCreateWindowEvent) !void {
        log.trace("CreateNotify for {}\n", .{ev.window});
    }

    fn _OnDestroyNotify(_: *Manager, ev: c.XDestroyWindowEvent) !void {
        log.trace("DestroyNotify for {}\n", .{ev.window});
    }

    fn _OnReparentNotify(_: *Manager, ev: c.XReparentEvent) !void {
        log.trace("ReparentNotify for {} to {}\n", .{ ev.window, ev.parent });
    }

    fn _OnMapNotify(_: *Manager, ev: c.XMapEvent) !void {
        log.trace("MapNotify for {}\n", .{ev.window});
    }

    fn _OnUnmapNotify(m: *Manager, ev: c.XUnmapEvent) !void {
        log.trace("UnmapNotify for {}\n", .{ev.window});
        const w = ev.window;
        if (ev.event == m.r) {
            log.trace("ignore UnmapNotify for reparented pre-existing window {}\n", .{w});
        } else if (m.clients.get(w) == null) {
            log.trace("ignore UnmapNotify for non-client window {}\n", .{w});
        } else {
            try m.unframeWindow(w);
        }
    }

    fn _OnConfigureRequest(m: *Manager, ev: c.XConfigureRequestEvent) !void {
        log.trace("ConfigureRequest for {}\n", .{ev.window});
        var changes = c.XWindowChanges{
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
            w = frame;
            log.info("resizing frame, ", .{});
        }
        _ = c.XConfigureWindow(m.d, w, @intCast(c_uint, ev.value_mask), &changes);
        log.info("resize {} to ({}, {})\n", .{ w, changes.width, changes.height });
    }

    fn frameWindow(m: *Manager, w: c.Window, wo: WindowOrigin) !void {
        const border_width = 3;
        const border_color = 0xff0000;
        const bg_color = 0x0000ff;

        var wattr: c.XWindowAttributes = undefined;
        if (c.XGetWindowAttributes(m.d, w, &wattr) == 0) return ZwmErrors.Error;
        if (wo == WindowOrigin.CreatedBeforeWM and ((wattr.override_redirect != 0 or wattr.map_state != c.IsViewable))) {
            return;
        }

        const frame = c.XCreateSimpleWindow(
            m.d,
            m.r,
            wattr.x,
            wattr.y,
            @intCast(c_uint, wattr.width),
            @intCast(c_uint, wattr.height),
            border_width,
            border_color,
            bg_color,
        );
        _ = c.XSelectInput(m.d, frame, c.SubstructureRedirectMask | c.SubstructureNotifyMask);
        _ = c.XAddToSaveSet(m.d, w);
        _ = c.XReparentWindow(m.d, w, frame, 0, 0);
        _ = c.XMapWindow(m.d, frame);
        try m.clients.put(w, frame);
        log.info("framed window {} [{}]\n", .{ w, frame });
    }

    fn unframeWindow(m: *Manager, w: c.Window) !void {
        const frame = m.clients.get(w) orelse return ZwmErrors.Error;
        _ = c.XUnmapWindow(m.d, frame);
        _ = c.XReparentWindow(m.d, w, m.r, 0, 0);
        _ = c.XRemoveFromSaveSet(m.d, w);
        _ = c.XDestroyWindow(m.d, frame);
        _ = m.clients.remove(w);
        log.info("unframed window {} [{}]\n", .{ w, frame });
    }

    fn _OnMapRequest(m: *Manager, ev: c.XMapRequestEvent) !void {
        log.trace("MapRequest for {}\n", .{ev.window});
        try m.frameWindow(ev.window, WindowOrigin.CreatedAfterWM);
        _ = c.XMapWindow(m.d, ev.window);
    }

    pub fn Run(m: *Manager) !void {
        try m._InitWm();
        try m._EventLoop();
    }

    fn on_wmdetected(_: ?*c.Display, err: [*c]c.XErrorEvent) callconv(.C) c_int {
        const e: *c.XErrorEvent = err;
        std.debug.assert(e.error_code == c.BadAccess);
        Manager.ce = ZwmErrors.OtherWMRunning;
        return 0;
    }

    fn on_xerror(d: ?*c.Display, err: [*c]c.XErrorEvent) callconv(.C) c_int {
        const e: *c.XErrorEvent = err;
        var error_text: [1024:0]u8 = undefined;
        _ = c.XGetErrorText(d, e.error_code, @ptrCast([*c]u8, &error_text), @sizeOf(@TypeOf(error_text)));
        log.err("ErrorEvent: request '{s}' xid {x}, error text '{s}'\n", .{
            util.xRequestCodeToString(e.request_code),
            e.resourceid,
            error_text,
        });
        Manager.ce = ZwmErrors.Error;
        return 0;
    }
};

pub fn main() !void {
    log.info("starting\n", .{});

    var m = try Manager.init(null);
    defer m.deinit();

    try m.Run();

    log.info("exiting\n", .{});
}
