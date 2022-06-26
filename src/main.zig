const std = @import("std");
const c = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xproto.h");
});

const textRed = "\x1b[31m";
const textGray = "\x1b[90m";
const textReset = "\x1b[0m";

fn log(comptime s: []const u8) void {
    std.debug.print(s, .{});
}

fn logf(comptime s: []const u8, args: anytype) void {
    std.debug.print(s, args);
}

fn requestCodeToString(code: u8) ![]const u8 {
    return switch (code) {
        c.X_CreateWindow => "X_CreateWindow",
        c.X_ChangeWindowAttributes => "X_ChangeWindowAttributes",
        c.X_GetWindowAttributes => "X_GetWindowAttributes",
        c.X_DestroyWindow => "X_DestroyWindow",
        c.X_DestroySubwindows => "X_DestroySubwindows",
        c.X_ChangeSaveSet => "X_ChangeSaveSet",
        c.X_ReparentWindow => "X_ReparentWindow",
        c.X_MapWindow => "X_MapWindow",
        c.X_MapSubwindows => "X_MapSubwindows",
        c.X_UnmapWindow => "X_UnmapWindow",
        c.X_UnmapSubwindows => "X_UnmapSubwindows",
        c.X_ConfigureWindow => "X_ConfigureWindow",
        c.X_CirculateWindow => "X_CirculateWindow",
        c.X_GetGeometry => "X_GetGeometry",
        c.X_QueryTree => "X_QueryTree",
        c.X_InternAtom => "X_InternAtom",
        c.X_GetAtomName => "X_GetAtomName",
        c.X_ChangeProperty => "X_ChangeProperty",
        c.X_DeleteProperty => "X_DeleteProperty",
        c.X_GetProperty => "X_GetProperty",
        c.X_ListProperties => "X_ListProperties",
        c.X_SetSelectionOwner => "X_SetSelectionOwner",
        c.X_GetSelectionOwner => "X_GetSelectionOwner",
        c.X_ConvertSelection => "X_ConvertSelection",
        c.X_SendEvent => "X_SendEvent",
        c.X_GrabPointer => "X_GrabPointer",
        c.X_UngrabPointer => "X_UngrabPointer",
        c.X_GrabButton => "X_GrabButton",
        c.X_UngrabButton => "X_UngrabButton",
        c.X_ChangeActivePointerGrab => "X_ChangeActivePointerGrab",
        c.X_GrabKeyboard => "X_GrabKeyboard",
        c.X_UngrabKeyboard => "X_UngrabKeyboard",
        c.X_GrabKey => "X_GrabKey",
        c.X_UngrabKey => "X_UngrabKey",
        c.X_AllowEvents => "X_AllowEvents",
        c.X_GrabServer => "X_GrabServer",
        c.X_UngrabServer => "X_UngrabServer",
        c.X_QueryPointer => "X_QueryPointer",
        c.X_GetMotionEvents => "X_GetMotionEvents",
        c.X_TranslateCoords => "X_TranslateCoords",
        c.X_WarpPointer => "X_WarpPointer",
        c.X_SetInputFocus => "X_SetInputFocus",
        c.X_GetInputFocus => "X_GetInputFocus",
        c.X_QueryKeymap => "X_QueryKeymap",
        c.X_OpenFont => "X_OpenFont",
        c.X_CloseFont => "X_CloseFont",
        c.X_QueryFont => "X_QueryFont",
        c.X_QueryTextExtents => "X_QueryTextExtents",
        c.X_ListFonts => "X_ListFonts",
        c.X_ListFontsWithInfo => "X_ListFontsWithInfo",
        c.X_SetFontPath => "X_SetFontPath",
        c.X_GetFontPath => "X_GetFontPath",
        c.X_CreatePixmap => "X_CreatePixmap",
        c.X_FreePixmap => "X_FreePixmap",
        c.X_CreateGC => "X_CreateGC",
        c.X_ChangeGC => "X_ChangeGC",
        c.X_CopyGC => "X_CopyGC",
        c.X_SetDashes => "X_SetDashes",
        c.X_SetClipRectangles => "X_SetClipRectangles",
        c.X_FreeGC => "X_FreeGC",
        c.X_ClearArea => "X_ClearArea",
        c.X_CopyArea => "X_CopyArea",
        c.X_CopyPlane => "X_CopyPlane",
        c.X_PolyPoint => "X_PolyPoint",
        c.X_PolyLine => "X_PolyLine",
        c.X_PolySegment => "X_PolySegment",
        c.X_PolyRectangle => "X_PolyRectangle",
        c.X_PolyArc => "X_PolyArc",
        c.X_FillPoly => "X_FillPoly",
        c.X_PolyFillRectangle => "X_PolyFillRectangle",
        c.X_PolyFillArc => "X_PolyFillArc",
        c.X_PutImage => "X_PutImage",
        c.X_GetImage => "X_GetImage",
        c.X_PolyText8 => "X_PolyText8",
        c.X_PolyText16 => "X_PolyText16",
        c.X_ImageText8 => "X_ImageText8",
        c.X_ImageText16 => "X_ImageText16",
        c.X_CreateColormap => "X_CreateColormap",
        c.X_FreeColormap => "X_FreeColormap",
        c.X_CopyColormapAndFree => "X_CopyColormapAndFree",
        c.X_InstallColormap => "X_InstallColormap",
        c.X_UninstallColormap => "X_UninstallColormap",
        c.X_ListInstalledColormaps => "X_ListInstalledColormaps",
        c.X_AllocColor => "X_AllocColor",
        c.X_AllocNamedColor => "X_AllocNamedColor",
        c.X_AllocColorCells => "X_AllocColorCells",
        c.X_AllocColorPlanes => "X_AllocColorPlanes",
        c.X_FreeColors => "X_FreeColors",
        c.X_StoreColors => "X_StoreColors",
        c.X_StoreNamedColor => "X_StoreNamedColor",
        c.X_QueryColors => "X_QueryColors",
        c.X_LookupColor => "X_LookupColor",
        c.X_CreateCursor => "X_CreateCursor",
        c.X_CreateGlyphCursor => "X_CreateGlyphCursor",
        c.X_FreeCursor => "X_FreeCursor",
        c.X_RecolorCursor => "X_RecolorCursor",
        c.X_QueryBestSize => "X_QueryBestSize",
        c.X_QueryExtension => "X_QueryExtension",
        c.X_ListExtensions => "X_ListExtensions",
        c.X_ChangeKeyboardMapping => "X_ChangeKeyboardMapping",
        c.X_GetKeyboardMapping => "X_GetKeyboardMapping",
        c.X_ChangeKeyboardControl => "X_ChangeKeyboardControl",
        c.X_GetKeyboardControl => "X_GetKeyboardControl",
        c.X_Bell => "X_Bell",
        c.X_ChangePointerControl => "X_ChangePointerControl",
        c.X_GetPointerControl => "X_GetPointerControl",
        c.X_SetScreenSaver => "X_SetScreenSaver",
        c.X_GetScreenSaver => "X_GetScreenSaver",
        c.X_ChangeHosts => "X_ChangeHosts",
        c.X_ListHosts => "X_ListHosts",
        c.X_SetAccessControl => "X_SetAccessControl",
        c.X_SetCloseDownMode => "X_SetCloseDownMode",
        c.X_KillClient => "X_KillClient",
        c.X_RotateProperties => "X_RotateProperties",
        c.X_ForceScreenSaver => "X_ForceScreenSaver",
        c.X_SetPointerMapping => "X_SetPointerMapping",
        c.X_GetPointerMapping => "X_GetPointerMapping",
        c.X_SetModifierMapping => "X_SetModifierMapping",
        c.X_GetModifierMapping => "X_GetModifierMapping",
        c.X_NoOperation => "X_NoOperation",
        else => return ZwmErrors.Error,
    };
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
        log("destroyed wm\n");
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
        log("initialized wm\n");
    }

    fn _EventLoop(m: *Manager) !void {
        while (true) {
            var e: c.XEvent = undefined;
            _ = c.XNextEvent(m.d, &e);
            const ename = event_name[@intCast(usize, e.type)];
            logf("{s}received event {s}{s}\n", .{ textGray, ename, textReset });
            try switch (e.type) {
                c.CreateNotify => m._OnCreateNotify(e.xcreatewindow),
                c.DestroyNotify => m._OnDestroyNotify(e.xdestroywindow),
                c.ReparentNotify => m._OnReparentNotify(e.xreparent),
                c.MapNotify => m._OnMapNotify(e.xmap),
                c.UnmapNotify => m._OnUnmapNotify(e.xunmap),
                c.ConfigureRequest => m._OnConfigureRequest(e.xconfigurerequest),
                c.MapRequest => m._OnMapRequest(e.xmaprequest),
                else => logf("{s}ignored event {s}{s}\n", .{ textGray, ename, textReset }),
            };
        }
    }

    fn _OnCreateNotify(_: *Manager, ev: c.XCreateWindowEvent) !void {
        logf("{s}(i) CreateNotify for {}{s}\n", .{ textGray, ev.window, textReset });
    }

    fn _OnDestroyNotify(_: *Manager, ev: c.XDestroyWindowEvent) !void {
        logf("{s}(i) DestroyNotify for {}{s}\n", .{ textGray, ev.window, textReset });
    }

    fn _OnReparentNotify(_: *Manager, ev: c.XReparentEvent) !void {
        logf("{s}(i) ReparentNotify for {} to {}{s}\n", .{ textGray, ev.window, ev.parent, textReset });
    }

    fn _OnMapNotify(_: *Manager, ev: c.XMapEvent) !void {
        logf("{s}(i) MapNotify for {}{s}\n", .{ textGray, ev.window, textReset });
    }

    fn _OnUnmapNotify(m: *Manager, ev: c.XUnmapEvent) !void {
        logf("{s}UnmapNotify for {}{s}\n", .{ textGray, ev.window, textReset });
        const w = ev.window;
        if (ev.event == m.r) {
            logf("{s}(i) ignore UnmapNotify for reparented pre-existing window {}{s}\n", .{ textGray, w, textReset });
        } else if (m.clients.get(w) == null) {
            logf("{s}(i) ignore UnmapNotify for non-client window {}{s}\n", .{ textGray, w, textReset });
        } else {
            try m.unframeWindow(w);
        }
    }

    fn _OnConfigureRequest(m: *Manager, ev: c.XConfigureRequestEvent) !void {
        logf("{s}ConfigureRequest for {}{s}\n", .{ textGray, ev.window, textReset });
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
            log("resizing frame, ");
        }
        _ = c.XConfigureWindow(m.d, w, @intCast(c_uint, ev.value_mask), &changes);
        logf("resize {} to ({}, {})\n", .{ w, changes.width, changes.height });
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
        logf("framed window {} [{}]\n", .{ w, frame });
    }

    fn unframeWindow(m: *Manager, w: c.Window) !void {
        const frame = m.clients.get(w) orelse return ZwmErrors.Error;
        _ = c.XUnmapWindow(m.d, frame);
        _ = c.XReparentWindow(m.d, w, m.r, 0, 0);
        _ = c.XRemoveFromSaveSet(m.d, w);
        _ = c.XDestroyWindow(m.d, frame);
        _ = m.clients.remove(w);
        logf("unframed window {} [{}]\n", .{ w, frame });
    }

    fn _OnMapRequest(m: *Manager, ev: c.XMapRequestEvent) !void {
        logf("{s}MapRequest for {}{s}\n", .{ textGray, ev.window, textReset });
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
        logf("{s}ErrorEvent: request '{s}' xid {x}, error text '{s}'{s}\n", .{
            textRed,
            requestCodeToString(e.request_code),
            e.resourceid,
            error_text,
            textReset,
        });
        Manager.ce = ZwmErrors.Error;
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
