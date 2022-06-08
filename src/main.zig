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

    var ce: ?ZwmErrors = null;

    pub fn Create(display: ?[]u8) !Manager {
        _ = display;
        const d = c.XOpenDisplay(":1") orelse return ZwmErrors.Error;
        const r = c.XDefaultRootWindow(d);
        return Manager{ .d = d, .r = r };
    }

    pub fn Destroy(m: Manager) void {
        _ = c.XCloseDisplay(m.d);
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

    fn _EventLoop(m: Manager) !void {
        while (true) {
            var e: c.XEvent = undefined;
            _ = c.XNextEvent(m.d, &e);
            const ename = event_name[@intCast(usize, e.type)];
            logf("received event {s}\n", .{ename});
            try switch (e.type) {
                c.CreateNotify => m._OnCreateNotify(e.xcreatewindow),
                c.DestroyNotify => m._OnDestroyNotify(e.xdestroywindow),
                c.ReparentNotify => m._OnReparentNotify(e.xreparent),
                c.ConfigureRequest => m._OnConfigureRequest(e.xconfigurerequest),
                c.MapRequest => m._OnMapRequest(e.xmaprequest),
                else => logf("ignored event {s}\n", .{ename}),
            };
        }
    }

    fn _OnCreateNotify(m: Manager, ev: c.XCreateWindowEvent) !void {
        _ = m;
        _ = ev;
    }

    fn _OnDestroyNotify(m: Manager, ev: c.XDestroyWindowEvent) !void {
        _ = m;
        _ = ev;
    }

    fn _OnReparentNotify(m: Manager, ev: c.XReparentEvent) !void {
        _ = m;
        _ = ev;
    }

    fn _OnConfigureRequest(m: Manager, ev: c.XConfigureRequestEvent) !void {
        var changes = c.XWindowChanges{
            .x = ev.x,
            .y = ev.y,
            .width = ev.width,
            .height = ev.height,
            .border_width = ev.border_width,
            .sibling = ev.above,
            .stack_mode = ev.detail,
        };
        _ = c.XConfigureWindow(m.d, ev.window, @intCast(c_uint, ev.value_mask), &changes);
        logf("resize {} to ({}, {})\n", .{ ev.window, changes.width, changes.height });
    }

    fn _OnMapRequest(m: Manager, ev: c.XMapRequestEvent) !void {
        _ = c.XMapWindow(m.d, ev.window);
    }

    pub fn Run(m: Manager) !void {
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

    const m = try Manager.Create(null);
    defer m.Destroy();

    try m.Run();

    log("exiting\n");
}
