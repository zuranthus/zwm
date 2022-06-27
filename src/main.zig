const std = @import("std");
const c = @import("x11.zig");
const util = @import("util.zig");
const log = @import("./log.zig");

const Manager = struct {
    d: *c.Display,
    root: c.Window,
    clients: std.AutoHashMap(c.Window, c.Window),

    pub fn init(display: ?[]u8) !Manager {
        _ = display;
        const d = c.XOpenDisplay(":1") orelse return error.CannotOpenDisplay;
        const r = c.XDefaultRootWindow(d);
        return Manager{
            .d = d,
            .root = r,
            .clients = std.AutoHashMap(c.Window, c.Window).init(std.heap.c_allocator),
        };
    }

    pub fn deinit(m: *Manager) void {
        _ = c.XCloseDisplay(m.d);
        // TODO deinit clients
        m.clients.deinit();
        log.info("destroyed wm", .{});
    }

    pub fn run(m: *Manager) !void {
        try m.initWm();
        try m.startEventLoop();
    }

    const WindowOrigin = enum { CreatedBeforeWM, CreatedAfterWM };
    var isWmDetected = false;

    fn initWm(m: *Manager) !void {
        _ = c.XSetErrorHandler(onWmDetected);
        _ = c.XSelectInput(m.d, m.root, c.SubstructureRedirectMask | c.SubstructureNotifyMask);
        _ = c.XSync(m.d, 0);
        if (Manager.isWmDetected) return error.AnotherWmDetected;

        _ = c.XSetErrorHandler(onXError);

        _ = c.XGrabServer(m.d);
        defer _ = c.XUngrabServer(m.d);

        var root: c.Window = undefined;
        var parent: c.Window = undefined;
        var ws: [*c]c.Window = undefined;
        var nws: c_uint = 0;
        _ = c.XQueryTree(m.d, m.root, &root, &parent, &ws, &nws);
        defer _ = c.XFree(ws);
        std.debug.assert(root == m.root);

        var i: usize = 0;
        while (i < nws) : (i += 1) {
            try m.frameWindow(ws[i], WindowOrigin.CreatedBeforeWM);
        }
        log.info("initialized wm", .{});
    }

    fn startEventLoop(m: *Manager) !void {
        while (true) {
            var e: c.XEvent = undefined;
            _ = c.XNextEvent(m.d, &e);
            const ename = util.xEventTypeToString(@intCast(u8, e.type));
            try switch (e.type) {
                c.CreateNotify => m.onCreateNotify(e.xcreatewindow),
                c.DestroyNotify => m.onDestroyNotify(e.xdestroywindow),
                c.ReparentNotify => m.onReparentNotify(e.xreparent),
                c.MapNotify => m.onMapNotify(e.xmap),
                c.UnmapNotify => m.onUnmapNotify(e.xunmap),
                c.ConfigureRequest => m.onConfigureRequest(e.xconfigurerequest),
                c.MapRequest => m.onMapRequest(e.xmaprequest),
                else => log.trace("ignored event {s}", .{ename}),
            };
        }
    }

    fn onWmDetected(_: ?*c.Display, err: [*c]c.XErrorEvent) callconv(.C) c_int {
        const e: *c.XErrorEvent = err;
        std.debug.assert(e.error_code == c.BadAccess);
        Manager.isWmDetected = true;
        return 0;
    }

    fn onXError(d: ?*c.Display, err: [*c]c.XErrorEvent) callconv(.C) c_int {
        const e: *c.XErrorEvent = err;
        var error_text: [1024:0]u8 = undefined;
        _ = c.XGetErrorText(d, e.error_code, @ptrCast([*c]u8, &error_text), @sizeOf(@TypeOf(error_text)));
        log.err("ErrorEvent: request '{s}' xid {x}, error text '{s}'", .{
            util.xRequestCodeToString(e.request_code),
            e.resourceid,
            error_text,
        });
        return 0;
    }

    fn onCreateNotify(_: *Manager, ev: c.XCreateWindowEvent) !void {
        log.trace("CreateNotify for {}", .{ev.window});
    }

    fn onDestroyNotify(_: *Manager, ev: c.XDestroyWindowEvent) !void {
        log.trace("DestroyNotify for {}", .{ev.window});
    }

    fn onReparentNotify(_: *Manager, ev: c.XReparentEvent) !void {
        log.trace("ReparentNotify for {} to {}", .{ ev.window, ev.parent });
    }

    fn onMapNotify(_: *Manager, ev: c.XMapEvent) !void {
        log.trace("MapNotify for {}", .{ev.window});
    }

    fn onUnmapNotify(m: *Manager, ev: c.XUnmapEvent) !void {
        log.trace("UnmapNotify for {}", .{ev.window});
        const w = ev.window;
        if (ev.event == m.root) {
            log.trace("ignore UnmapNotify for reparented pre-existing window {}", .{w});
        } else if (m.clients.get(w) == null) {
            log.trace("ignore UnmapNotify for non-client window {}", .{w});
        } else {
            try m.unframeWindow(w);
        }
    }

    fn onConfigureRequest(m: *Manager, ev: c.XConfigureRequestEvent) !void {
        log.trace("ConfigureRequest for {}", .{ev.window});
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
        log.info("resize {} to ({}, {})", .{ w, changes.width, changes.height });
    }

    fn onMapRequest(m: *Manager, ev: c.XMapRequestEvent) !void {
        log.trace("MapRequest for {}", .{ev.window});
        try m.frameWindow(ev.window, WindowOrigin.CreatedAfterWM);
        _ = c.XMapWindow(m.d, ev.window);
    }

    fn frameWindow(m: *Manager, w: c.Window, wo: WindowOrigin) !void {
        const border_width = 3;
        const border_color = 0xff0000;
        const bg_color = 0x0000ff;

        var wattr: c.XWindowAttributes = undefined;
        if (c.XGetWindowAttributes(m.d, w, &wattr) == 0) return error.Error;
        if (wo == WindowOrigin.CreatedBeforeWM and ((wattr.override_redirect != 0 or wattr.map_state != c.IsViewable))) {
            return;
        }

        const frame = c.XCreateSimpleWindow(
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
        _ = c.XSelectInput(m.d, frame, c.SubstructureRedirectMask | c.SubstructureNotifyMask);
        _ = c.XAddToSaveSet(m.d, w);
        _ = c.XReparentWindow(m.d, w, frame, 0, 0);
        _ = c.XMapWindow(m.d, frame);
        try m.clients.put(w, frame);
        log.info("framed window {} [{}]", .{ w, frame });
    }

    fn unframeWindow(m: *Manager, w: c.Window) !void {
        const frame = m.clients.get(w) orelse return error.WindowIsNotClient;
        _ = c.XUnmapWindow(m.d, frame);
        _ = c.XReparentWindow(m.d, w, m.root, 0, 0);
        _ = c.XRemoveFromSaveSet(m.d, w);
        _ = c.XDestroyWindow(m.d, frame);
        _ = m.clients.remove(w);
        log.info("unframed window {} [{}]", .{ w, frame });
    }
};

pub fn main() !void {
    log.info("starting", .{});

    var m = try Manager.init(null);
    defer m.deinit();

    try m.run();

    log.info("exiting", .{});
}
