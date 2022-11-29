const std = @import("std");
const log = @import("log.zig");
const atoms = @import("atoms.zig");
const x = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xproto.h");
    @cInclude("X11/Xutil.h");
    @cInclude("X11/Xatom.h");
    @cInclude("X11/cursorfont.h");
});

pub usingnamespace x;

/// Unmaps the window and assigns WM_STATE == IconicState.
pub fn hideWindow(d: *x.Display, w: x.Window) void {
    const substructure_notify = SubstructureNotifyController.disable(d);
    defer substructure_notify.enable();

    _ = x.XUnmapWindow(d, w);
    setWindowWMState(d, w, x.IconicState); // TODO: also set _NET_WM_STATE_HIDDEN?
}

/// Maps the window and assigns WM_STATE = NormalState.
pub fn unhideWindow(d: *x.Display, w: x.Window) void {
    const substructure_notify = SubstructureNotifyController.disable(d);
    defer substructure_notify.enable();

    _ = x.XMapWindow(d, w);
    setWindowWMState(d, w, x.NormalState);
}

/// Assigns the value of WM_STATE property to wm_state.
/// Possible values: NormalState, IconicState, WithdrawnState.
pub fn setWindowWMState(d: *x.Display, w: x.Window, wm_state: i32) void {
    std.debug.assert(wm_state == x.NormalState or wm_state == x.IconicState or wm_state == x.WithdrawnState);
    setWindowProperty(d, w, atoms.wm_state, atoms.wm_state, [_]c_ulong{ @intCast(c_ulong, wm_state), x.None });
}

/// Returns the value of WM_STATE property or null if it is not set.
/// Possible values: NormalState, IconicState, WithdrawnState.
pub fn getWindowWMState(d: *x.Display, w: x.Window) ?i32 {
    if (getWindowProperty(d, w, atoms.wm_state, atoms.wm_state, x.Atom)) |state|
        return @intCast(i32, state);
    return null;
}

pub fn getWindowProperty(d: *x.Display, w: x.Window, property: x.Atom, property_type: x.Atom, comptime dataType: type) ?dataType {
    var result: ?dataType = null;
    var actual_type: x.Atom = undefined;
    var actual_format: c_int = undefined;
    var nitems: c_ulong = undefined;
    var bytes_left: c_ulong = undefined;
    var data_ptr: ?*dataType = null;
    if (x.XGetWindowProperty(
        d,
        w,
        property,
        0,
        @bitSizeOf(dataType) / @sizeOf(c_ulong),
        0,
        property_type,
        &actual_type,
        &actual_format,
        &nitems,
        &bytes_left,
        @ptrCast([*]?[*]u8, &data_ptr),
    ) == x.Success and data_ptr != null) {
        result = data_ptr.?.*;
        _ = x.XFree(data_ptr);
    }
    return result;
}

pub fn setWindowProperty(d: *x.Display, w: x.Window, property: x.Atom, property_type: x.Atom, data: anytype) void {
    const num = @sizeOf(@TypeOf(data)) / @sizeOf(c_ulong);
    _ = x.XChangeProperty(d, w, property, property_type, 32, x.PropModeReplace, std.mem.asBytes(&data), num);
}

pub fn getAtomName(d: *x.Display, atom: x.Atom, outName: *[128]u8) bool {
    const atom_name = x.XGetAtomName(d, atom);
    if (atom_name) |name| {
        std.mem.copy(u8, outName, std.mem.span(name));
        _ = x.XFree(atom_name);
        return true;
    }
    outName[0] = 0;
    return false;
}

const SubstructureNotifyController = struct {
    display: *x.Display,
    event_mask: ?c_long = null,

    pub fn disable(d: *x.Display) @This() {
        var self = SubstructureNotifyController{ .display = d };
        const root = x.XDefaultRootWindow(d);
        var wa: x.XWindowAttributes = undefined;
        if (x.XGetWindowAttributes(d, root, &wa) != 0) {
            self.event_mask = wa.your_event_mask;
            var swa = std.mem.zeroes(x.XSetWindowAttributes);
            _ = x.XChangeWindowAttributes(d, root, x.CWEventMask, &swa);
        }
        return self;
    }

    pub fn enable(self: *const @This()) void {
        if (self.event_mask) |em| {
            const root = x.XDefaultRootWindow(self.display);
            var swa = std.mem.zeroInit(x.XSetWindowAttributes, .{ .event_mask = em });
            _ = x.XChangeWindowAttributes(self.display, root, x.CWEventMask, &swa);
        }
    }
};

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

pub fn eventTypeToString(t: u8) []const u8 {
    return event_name[t];
}

pub fn requestCodeToString(code: u8) ![]const u8 {
    return switch (code) {
        x.X_CreateWindow => "X_CreateWindow",
        x.X_ChangeWindowAttributes => "X_ChangeWindowAttributes",
        x.X_GetWindowAttributes => "X_GetWindowAttributes",
        x.X_DestroyWindow => "X_DestroyWindow",
        x.X_DestroySubwindows => "X_DestroySubwindows",
        x.X_ChangeSaveSet => "X_ChangeSaveSet",
        x.X_ReparentWindow => "X_ReparentWindow",
        x.X_MapWindow => "X_MapWindow",
        x.X_MapSubwindows => "X_MapSubwindows",
        x.X_UnmapWindow => "X_UnmapWindow",
        x.X_UnmapSubwindows => "X_UnmapSubwindows",
        x.X_ConfigureWindow => "X_ConfigureWindow",
        x.X_CirculateWindow => "X_CirculateWindow",
        x.X_GetGeometry => "X_GetGeometry",
        x.X_QueryTree => "X_QueryTree",
        x.X_InternAtom => "X_InternAtom",
        x.X_GetAtomName => "X_GetAtomName",
        x.X_ChangeProperty => "X_ChangeProperty",
        x.X_DeleteProperty => "X_DeleteProperty",
        x.X_GetProperty => "X_GetProperty",
        x.X_ListProperties => "X_ListProperties",
        x.X_SetSelectionOwner => "X_SetSelectionOwner",
        x.X_GetSelectionOwner => "X_GetSelectionOwner",
        x.X_ConvertSelection => "X_ConvertSelection",
        x.X_SendEvent => "X_SendEvent",
        x.X_GrabPointer => "X_GrabPointer",
        x.X_UngrabPointer => "X_UngrabPointer",
        x.X_GrabButton => "X_GrabButton",
        x.X_UngrabButton => "X_UngrabButton",
        x.X_ChangeActivePointerGrab => "X_ChangeActivePointerGrab",
        x.X_GrabKeyboard => "X_GrabKeyboard",
        x.X_UngrabKeyboard => "X_UngrabKeyboard",
        x.X_GrabKey => "X_GrabKey",
        x.X_UngrabKey => "X_UngrabKey",
        x.X_AllowEvents => "X_AllowEvents",
        x.X_GrabServer => "X_GrabServer",
        x.X_UngrabServer => "X_UngrabServer",
        x.X_QueryPointer => "X_QueryPointer",
        x.X_GetMotionEvents => "X_GetMotionEvents",
        x.X_TranslateCoords => "X_TranslateCoords",
        x.X_WarpPointer => "X_WarpPointer",
        x.X_SetInputFocus => "X_SetInputFocus",
        x.X_GetInputFocus => "X_GetInputFocus",
        x.X_QueryKeymap => "X_QueryKeymap",
        x.X_OpenFont => "X_OpenFont",
        x.X_CloseFont => "X_CloseFont",
        x.X_QueryFont => "X_QueryFont",
        x.X_QueryTextExtents => "X_QueryTextExtents",
        x.X_ListFonts => "X_ListFonts",
        x.X_ListFontsWithInfo => "X_ListFontsWithInfo",
        x.X_SetFontPath => "X_SetFontPath",
        x.X_GetFontPath => "X_GetFontPath",
        x.X_CreatePixmap => "X_CreatePixmap",
        x.X_FreePixmap => "X_FreePixmap",
        x.X_CreateGC => "X_CreateGC",
        x.X_ChangeGC => "X_ChangeGC",
        x.X_CopyGC => "X_CopyGC",
        x.X_SetDashes => "X_SetDashes",
        x.X_SetClipRectangles => "X_SetClipRectangles",
        x.X_FreeGC => "X_FreeGC",
        x.X_ClearArea => "X_ClearArea",
        x.X_CopyArea => "X_CopyArea",
        x.X_CopyPlane => "X_CopyPlane",
        x.X_PolyPoint => "X_PolyPoint",
        x.X_PolyLine => "X_PolyLine",
        x.X_PolySegment => "X_PolySegment",
        x.X_PolyRectangle => "X_PolyRectangle",
        x.X_PolyArc => "X_PolyArc",
        x.X_FillPoly => "X_FillPoly",
        x.X_PolyFillRectangle => "X_PolyFillRectangle",
        x.X_PolyFillArc => "X_PolyFillArc",
        x.X_PutImage => "X_PutImage",
        x.X_GetImage => "X_GetImage",
        x.X_PolyText8 => "X_PolyText8",
        x.X_PolyText16 => "X_PolyText16",
        x.X_ImageText8 => "X_ImageText8",
        x.X_ImageText16 => "X_ImageText16",
        x.X_CreateColormap => "X_CreateColormap",
        x.X_FreeColormap => "X_FreeColormap",
        x.X_CopyColormapAndFree => "X_CopyColormapAndFree",
        x.X_InstallColormap => "X_InstallColormap",
        x.X_UninstallColormap => "X_UninstallColormap",
        x.X_ListInstalledColormaps => "X_ListInstalledColormaps",
        x.X_AllocColor => "X_AllocColor",
        x.X_AllocNamedColor => "X_AllocNamedColor",
        x.X_AllocColorCells => "X_AllocColorCells",
        x.X_AllocColorPlanes => "X_AllocColorPlanes",
        x.X_FreeColors => "X_FreeColors",
        x.X_StoreColors => "X_StoreColors",
        x.X_StoreNamedColor => "X_StoreNamedColor",
        x.X_QueryColors => "X_QueryColors",
        x.X_LookupColor => "X_LookupColor",
        x.X_CreateCursor => "X_CreateCursor",
        x.X_CreateGlyphCursor => "X_CreateGlyphCursor",
        x.X_FreeCursor => "X_FreeCursor",
        x.X_RecolorCursor => "X_RecolorCursor",
        x.X_QueryBestSize => "X_QueryBestSize",
        x.X_QueryExtension => "X_QueryExtension",
        x.X_ListExtensions => "X_ListExtensions",
        x.X_ChangeKeyboardMapping => "X_ChangeKeyboardMapping",
        x.X_GetKeyboardMapping => "X_GetKeyboardMapping",
        x.X_ChangeKeyboardControl => "X_ChangeKeyboardControl",
        x.X_GetKeyboardControl => "X_GetKeyboardControl",
        x.X_Bell => "X_Bell",
        x.X_ChangePointerControl => "X_ChangePointerControl",
        x.X_GetPointerControl => "X_GetPointerControl",
        x.X_SetScreenSaver => "X_SetScreenSaver",
        x.X_GetScreenSaver => "X_GetScreenSaver",
        x.X_ChangeHosts => "X_ChangeHosts",
        x.X_ListHosts => "X_ListHosts",
        x.X_SetAccessControl => "X_SetAccessControl",
        x.X_SetCloseDownMode => "X_SetCloseDownMode",
        x.X_KillClient => "X_KillClient",
        x.X_RotateProperties => "X_RotateProperties",
        x.X_ForceScreenSaver => "X_ForceScreenSaver",
        x.X_SetPointerMapping => "X_SetPointerMapping",
        x.X_GetPointerMapping => "X_GetPointerMapping",
        x.X_SetModifierMapping => "X_SetModifierMapping",
        x.X_GetModifierMapping => "X_GetModifierMapping",
        x.X_NoOperation => "X_NoOperation",
        else => return error.InvalidArgument,
    };
}
