const x11 = @import("x11.zig");

pub var utf8_string: x11.Atom = undefined;
pub var zwm_main_factor: x11.Atom = undefined;
pub var wm_protocols: x11.Atom = undefined;
pub var wm_delete: x11.Atom = undefined;
pub var wm_take_focus: x11.Atom = undefined;
pub var wm_state: x11.Atom = undefined;
pub var wm_change_state: x11.Atom = undefined;
pub var net_supported: x11.Atom = undefined;
pub var net_wm_strut: x11.Atom = undefined;
pub var net_wm_strut_partial: x11.Atom = undefined;
pub var net_wm_window_type: x11.Atom = undefined;
pub var net_wm_window_type_dock: x11.Atom = undefined;
pub var net_wm_window_type_dialog: x11.Atom = undefined;
pub var net_wm_state: x11.Atom = undefined;
pub var net_wm_state_fullscreen: x11.Atom = undefined;
pub var net_wm_desktop: x11.Atom = undefined;
pub var net_number_of_desktops: x11.Atom = undefined;
pub var net_current_desktop: x11.Atom = undefined;
pub var net_active_window: x11.Atom = undefined;
pub var net_client_list: x11.Atom = undefined;
pub var net_supporting_wm_check: x11.Atom = undefined;

pub fn init(d: *x11.Display) void {
    utf8_string = x11.XInternAtom(d, "UTF8_STRING", 0);
    zwm_main_factor = x11.XInternAtom(d, "ZWM_MAIN_FACTOR", 0);
    wm_protocols = x11.XInternAtom(d, "WM_PROTOCOLS", 0);
    wm_delete = x11.XInternAtom(d, "WM_DELETE_WINDOW", 0);
    wm_take_focus = x11.XInternAtom(d, "WM_TAKE_FOCUS", 0);
    wm_state = x11.XInternAtom(d, "WM_STATE", 0);
    wm_change_state = x11.XInternAtom(d, "WM_CHANGE_STATE", 0);
    net_supported = x11.XInternAtom(d, "_NET_SUPPORTED", 0);
    net_wm_strut = x11.XInternAtom(d, "_NET_WM_STRUT", 0);
    net_wm_strut_partial = x11.XInternAtom(d, "_NET_WM_STRUT_PARTIAL", 0);
    net_wm_window_type = x11.XInternAtom(d, "_NET_WM_WINDOW_TYPE", 0);
    net_wm_window_type_dock = x11.XInternAtom(d, "_NET_WM_WINDOW_TYPE_DOCK", 0);
    net_wm_window_type_dialog = x11.XInternAtom(d, "_NET_WM_WINDOW_TYPE_DIALOG", 0);
    net_wm_state = x11.XInternAtom(d, "_NET_WM_STATE", 0);
    net_wm_state_fullscreen = x11.XInternAtom(d, "_NET_WM_STATE_FULLSCREEN", 0);
    net_wm_desktop = x11.XInternAtom(d, "_NET_WM_DESKTOP", 0);
    net_number_of_desktops = x11.XInternAtom(d, "_NET_NUMBER_OF_DESKTOPS", 0);
    net_current_desktop = x11.XInternAtom(d, "_NET_CURRENT_DESKTOP", 0);
    net_active_window = x11.XInternAtom(d, "_NET_ACTIVE_WINDOW", 0);
    net_client_list = x11.XInternAtom(d, "_NET_CLIENT_LIST", 0);
    net_supporting_wm_check = x11.XInternAtom(d, "_NET_SUPPORTING_WM_CHECK", 0);

    const supported_net_atoms = [_]x11.Atom{
        net_supported,
        net_wm_strut,
        net_wm_strut_partial,
        net_wm_window_type,
        net_wm_window_type_dock,
        net_wm_window_type_dialog,
        net_wm_state,
        net_wm_state_fullscreen,
        net_wm_desktop,
        net_number_of_desktops,
        net_current_desktop,
        net_active_window,
        net_client_list,
        net_supporting_wm_check,
    };
    _ = x11.XChangeProperty(
        d,
        x11.XDefaultRootWindow(d),
        net_supported,
        x11.XA_ATOM,
        32,
        x11.PropModeReplace,
        @ptrCast([*c]const u8, &supported_net_atoms),
        supported_net_atoms.len,
    );
}

pub fn deinit(d: *x11.Display) void {
    _ = d;
}
