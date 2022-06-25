const std = @import("std");
const c = @cImport({
    @cInclude("X11/Xlib.h");
});

fn log(comptime s: []const u8) void {
    std.debug.print(s, .{});
}

fn logf(comptime s: []const u8, args: anytype) void {
    std.debug.print(s, args);
}

const event_name = [_][]const u8{
    "KeyPress",
    "KeyPress",
    "KeyPress",
    "KeyRelease",
    "ButtonPress",
    "ButtonRelease",
    "MotionNotify",
    "EnterNotify",
    "LeaveNotify",
    "FocusIn",
    "FocusOut",
    "KeymapNotify",
    "Expose",
    "GraphicsExpose",
    "NoExpose",
    "VisibilityNotify",
    "CreateNotify",
    "DestroyNotify",
    "UnmapNotify",
    "MapNotify",
    "MapRequest",
    "ReparentNotify",
    "ConfigureNotify",
    "ConfigureRequest",
    "GravityNotify",
    "ResizeRequest",
    "CirculateNotify",
    "CirculateRequest",
    "PropertyNotify",
    "SelectionClear",
    "SelectionRequest",
    "SelectionNotify",
    "ColormapNotify",
    "ClientMessage",
    "MappingNotify",
    "GenericEvent",
};

const ZwmErrors = error{
    Error,
    OtherWMRunning,
};

const Manager = struct {
    d: *c.Display,
    r: c.Window,
    clients: std.AutoHashMap(c.Window, c.Window),

    var ce: ?ZwmErrors = null;

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
        log("destroyed wm\n");
    }

    fn _InitWm(m: Manager) !void {
        _ = c.XSetErrorHandler(on_wmdetected);
        _ = c.XSelectInput(m.d, m.r, c.SubstructureRedirectMask | c.SubstructureNotifyMask);
        _ = c.XSync(m.d, 0);
        if (Manager.ce) |err| return err;
        _ = c.XSetErrorHandler(on_xerror);
        log("initialized wm\n");
    }

    fn _EventLoop(m: *Manager) !void {
        while (true) {
            var e: c.XEvent = undefined;
            _ = c.XNextEvent(m.d, &e);
            const ename = event_name[@intCast(usize, e.type)];
            logf("received event {s}\n", .{ename});
            try switch (e.type) {
                c.CreateNotify => m._OnCreateNotify(e.xcreatewindow),
                c.DestroyNotify => m._OnDestroyNotify(e.xdestroywindow),
                c.ReparentNotify => m._OnReparentNotify(e.xreparent),
                c.MapNotify => m._OnMapNotify(e.xmap),
                c.ConfigureRequest => m._OnConfigureRequest(e.xconfigurerequest),
                c.MapRequest => m._OnMapRequest(e.xmaprequest),
                else => logf("ignored event {s}\n", .{ename}),
            };
        }
    }

    fn _OnCreateNotify(m: *Manager, ev: c.XCreateWindowEvent) !void {
        _ = m;
        _ = ev;
    }

    fn _OnDestroyNotify(m: *Manager, ev: c.XDestroyWindowEvent) !void {
        _ = m;
        _ = ev;
    }

    fn _OnReparentNotify(_: *Manager, _: c.XReparentEvent) !void {}

    fn _OnMapNotify(_: *Manager, _: c.XMapEvent) !void {}

    fn _OnConfigureRequest(m: *Manager, ev: c.XConfigureRequestEvent) !void {
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
            log("resizing frame:\n");
        }
        _ = c.XConfigureWindow(m.d, w, @intCast(c_uint, ev.value_mask), &changes);
        logf("resize {} to ({}, {})\n", .{ w, changes.width, changes.height });
    }

    fn frameWindow(m: *Manager, w: c.Window) !void {
        const border_width = 3;
        const border_color = 0xff0000;
        const bg_color = 0x0000ff;

        var wattr: c.XWindowAttributes = undefined;
        if (c.XGetWindowAttributes(m.d, w, &wattr) == 0) return ZwmErrors.Error;

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
        logf("framed window {} [{}]\n", .{ w, frame });
    }

    fn _OnMapRequest(m: *Manager, ev: c.XMapRequestEvent) !void {
        try m.frameWindow(ev.window);
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
        return 0;
    }
};

pub fn main() !void {
    log("starting\n");

    var m = try Manager.init(null);
    defer m.deinit();

    try m.Run();

    log("exiting\n");
}
