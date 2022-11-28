const std = @import("std");
const x11 = @import("x11.zig");
const log = @import("log.zig");
const config = @import("config.zig");
const commands = @import("commands.zig");
const util = @import("util.zig");
const clients_state = @import("clients_state.zig");
const atoms = @import("atoms.zig");
const vec = @import("vec.zig");
const Pos = vec.Pos;
const Size = vec.Size;
const Client = @import("client.zig").Client;
const TileLayout = @import("layout.zig").TileLayout;
const Workspace = @import("workspace.zig").Workspace;
const Monitor = @import("monitor.zig").Monitor;

pub const Manager = struct {
    const Self = @This();
    const ClientOwner = util.OwningList(Client);
    const root_event_mask = x11.SubstructureNotifyMask | x11.SubstructureRedirectMask;
    var is_instance_alive = false;

    display: *x11.Display = undefined,
    clients: ClientOwner = undefined,
    event_handler: EventHandler = undefined,
    monitor: Monitor = undefined,
    focused_client: ?*Client = null,
    layout_dirty: bool = false,
    exit_code: ?u8 = null,
    state_file: ?[]const u8 = null,
    dock_window: ?x11.Window = null,
    dock_struts: util.Struts = .{},

    pub fn deinit(self: *Self) void {
        if (!is_instance_alive) return;

        if (self.state_file) |file| {
            log.info("Saving state to {s}", .{file});
            clients_state.saveState(self, file) catch |e| {
                log.err("Cannot save clients state, error {}", .{e});
            };
        }

        _ = x11.XUngrabKey(self.display, x11.AnyKey, x11.AnyModifier, x11.XDefaultRootWindow(self.display));
        self.monitor.deinit();
        self.event_handler.deinit();
        self.clients.deinit();
        atoms.deinit(self.display);
        ErrorHandler.deregister();
        _ = x11.XCloseDisplay(self.display);
        is_instance_alive = false;
        log.info("Destroyed wm", .{});
    }

    pub fn run(self: *Self, display_name_arg: ?[:0]const u8, state_file_arg: ?[]const u8) !u8 {
        if (is_instance_alive) return error.WmInstanceAlreadyExists;
        const display_name: [:0]const u8 = if (display_name_arg) |name| name else ":0";
        const display = x11.XOpenDisplay(@ptrCast([*c]const u8, display_name)) orelse return error.CannotOpenDisplay;
        const root = x11.XDefaultRootWindow(display);
        if (isAnotherWmDetected(display, root)) {
            _ = x11.XCloseDisplay(display);
            return error.AnotherWmDetected;
        }

        is_instance_alive = true;
        self.display = display;
        ErrorHandler.register();
        atoms.init(display);
        self.clients = ClientOwner.init();
        self.event_handler = EventHandler.init(display, self);
        const screen = x11.XDefaultScreen(display);
        self.monitor = Monitor.init(
            Pos.init(0, 0),
            Size.init(
                x11.XDisplayWidth(display, screen),
                x11.XDisplayHeight(display, screen),
            ),
        );
        x11.setWindowProperty(self.display, root, atoms.net_number_of_desktops, x11.XA_CARDINAL, @intCast(c_ulong, self.monitor.workspaces.len));
        self.manageExistingWindows();
        var wa = std.mem.zeroes(x11.XSetWindowAttributes);
        // show cursor
        wa.cursor = x11.XCreateFontCursor(self.display, x11.XC_left_ptr);
        // select events
        wa.event_mask = root_event_mask;
        _ = x11.XChangeWindowAttributes(self.display, root, x11.CWCursor | x11.CWEventMask, &wa);
        // hotkeys
        _ = x11.XUngrabKey(self.display, x11.AnyKey, x11.AnyModifier, root);
        inline for (config.key_actions) |a|
            _ = x11.XGrabKey(
                self.display,
                x11.XKeysymToKeycode(self.display, a[1]),
                a[0],
                root,
                0,
                x11.GrabModeAsync,
                x11.GrabModeAsync,
            );

        self.state_file = state_file_arg;
        if (self.state_file) |file| {
            log.info("Loading state from {s}", .{file});
            clients_state.loadState(self, file) catch |e| {
                log.err("Cannot load clients state, error {}", .{e});
            };
        }

        // force-apply focus
        focusWorkspace(self, self.activeWorkspace().id);

        log.info("Created and initialized wm", .{});

        while (self.exit_code == null) {
            if (self.layout_dirty) self.applyLayout();
            try self.event_handler.processEvent();
        }

        if (self.exit_code) |code| return code;
        return 0;
    }

    pub fn activeMonitor(self: *Self) *Monitor {
        return &self.monitor;
    }

    pub fn activeWorkspace(self: *Self) *Workspace {
        return self.activeMonitor().activeWorkspace();
    }

    pub fn focusWorkspace(self: *Self, workspace_id: u8) void {
        // TODO: multi-monitor
        self.activeMonitor().activateWorkspace(workspace_id);
        self.applyLayout();
        if (self.activeClient() != self.focused_client) self.updateFocus();

        x11.setWindowProperty(
            self.display,
            x11.XDefaultRootWindow(self.display),
            atoms.net_current_desktop,
            x11.XA_CARDINAL,
            @intCast(c_ulong, self.monitor.active_workspace_id),
        );
    }

    pub fn activeClient(self: *Self) ?*Client {
        return self.activeWorkspace().active_client;
    }

    /// Activate and switch focus to client.
    /// Also activate its monitor and workspace if they are not active.
    pub fn focusClient(self: *Self, client: *Client) void {
        // TODO: revisit for multi-monitor support
        const client_workspace = &self.monitor.workspaces[client.workspace_id.?];
        client_workspace.activateClient(client);
        if (client_workspace.id == self.activeWorkspace().id) {
            if (self.activeClient() != self.focused_client) self.updateFocus();
        } else {
            self.focusWorkspace(client_workspace.id);
        }
    }

    pub fn focusNextClient(self: *Self) void {
        const w = self.activeWorkspace();
        std.debug.assert(self.focused_client != null);
        std.debug.assert(w.active_client == self.focused_client.?);
        w.activateNextClient();
        if (self.activeClient() != self.focused_client) self.updateFocus();
    }

    pub fn focusPrevClient(self: *Self) void {
        const w = self.activeWorkspace();
        std.debug.assert(self.focused_client != null);
        std.debug.assert(w.active_client == self.focused_client.?);
        w.activatePrevClient();
        if (self.activeClient() != self.focused_client) self.updateFocus();
    }

    pub fn moveClientToWorkspace(self: *Self, client: *Client, monitor_id: u8, workspace_id: u8) void {
        std.debug.assert(monitor_id == 0); // TODO: change after implementing multi-monitor support
        if (client.monitor_id == monitor_id and client.workspace_id == workspace_id) return;

        // Will need to update layout if moving to or from visible workspace
        const need_update_layout = client.workspace_id == self.activeWorkspace().id or workspace_id == self.activeWorkspace().id;

        self.monitor.removeClient(client);
        self.monitor.addClient(client, workspace_id);
        if (need_update_layout) self.applyLayout();
        if (self.activeClient() != self.focused_client) self.updateFocus();
        log.trace("Moved client {} to ({}, {})", .{ client.w, monitor_id, workspace_id });
    }

    pub fn markLayoutDirty(self: *Self) void {
        self.layout_dirty = true;
    }

    pub fn killClientWindow(self: *Self, client: *Client) void {
        self.event_handler.killWindow(client.w) catch unreachable;
    }

    pub fn toggleDockWindow(self: *Self) void {
        if (self.dock_window) |w| {
            if (x11.getWindowWMState(self.display, w) == x11.NormalState) {
                x11.hideWindow(self.display, w);
                self.applyStruts(.{});
            } else {
                x11.unhideWindow(self.display, w);
                self.applyStruts(self.dock_struts);
            }
        }
    }

    fn setClientFullscreen(self: *Self, c: *Client, is_fullscreen: bool) void {
        // TODO: remove border
        c.is_fullscreen = is_fullscreen;
        x11.setWindowProperty(
            self.display,
            c.w,
            atoms.net_wm_state,
            x11.XA_ATOM,
            if (is_fullscreen) atoms.net_wm_state_fullscreen else 0,
        );
        if (c.is_fullscreen) {
            const m = self.activeMonitor();
            c.moveResize(m.origin, m.size);
            self.markLayoutDirty();
        } else {
            if (c.is_floating) {
                c.moveResize(Pos.init(100, 100), Size.init(200, 200)); // TODO: save old size
            } else {
                self.markLayoutDirty();
            }
        }
    }

    /// Switch focus to the active client of the active workspace of the active monitor.
    fn updateFocus(self: *Self) void {
        const client = self.activeClient();
        const prev_focused_client = self.focused_client;
        self.focused_client = client;

        if (prev_focused_client) |c| {
            c.setFocusedBorder(false);
            self.grabMouseButtons(c);
        }

        if (client) |c| {
            // update border state and grab focus
            if (!c.is_fullscreen) c.setFocusedBorder(true);
            _ = x11.XSetInputFocus(self.display, c.w, x11.RevertToPointerRoot, x11.CurrentTime);
            _ = x11.XRaiseWindow(self.display, c.w);
            self.grabMouseButtons(c);
            log.info("Focused client {}", .{c.w});
        } else {
            // reset focus
            _ = x11.XSetInputFocus(self.display, x11.PointerRoot, x11.RevertToPointerRoot, x11.CurrentTime);
            log.info("Cleared focus", .{});
        }

        x11.setWindowProperty(
            self.display,
            x11.XDefaultRootWindow(self.display),
            atoms.net_active_window,
            x11.XA_WINDOW,
            if (self.focused_client) |c| c.w else x11.None,
        );
    }

    fn manageExistingWindows(self: *Self) void {
        const root = x11.XDefaultRootWindow(self.display);
        var unused_win: x11.Window = undefined;
        var windows: [*c]x11.Window = null;
        var num: c_uint = 0;
        _ = x11.XQueryTree(self.display, root, &unused_win, &unused_win, &windows, &num);
        defer _ = if (windows != null) x11.XFree(windows);
        if (num == 0) return;

        // Manage non-transient windows
        for (windows[0..num]) |w| {
            var wa = std.mem.zeroes(x11.XWindowAttributes);
            if (x11.XGetWindowAttributes(self.display, w, &wa) == 0) {
                log.err("XGetWindowAttributes failed for {}", .{w});
                continue;
            }
            if (x11.XGetTransientForHint(self.display, w, &unused_win) != 0)
                continue;

            // Only add windows that are visible or in iconic state
            if (wa.map_state == x11.IsViewable or x11.getWindowWMState(self.display, w) == x11.IconicState) {
                self.processNewWindow(w);
            } else {
                log.info("Ignoring hidden {}", .{w});
            }
        }

        // Manage transient windows
        for (windows[0..num]) |w| {
            var wa = std.mem.zeroes(x11.XWindowAttributes);
            if (x11.XGetWindowAttributes(self.display, w, &wa) == 0) {
                log.err("XGetWindowAttributes failed for {}", .{w});
                continue;
            }
            if (x11.XGetTransientForHint(self.display, w, &unused_win) == 0)
                continue;

            // Only add windows that are visible or in iconic state
            if (wa.map_state == x11.IsViewable or x11.getWindowWMState(self.display, w) == x11.IconicState) {
                self.processNewWindow(w);
            } else {
                log.info("Ignoring hidden transient {}", .{w});
            }
        }
    }

    fn processNewWindow(self: *Self, w: x11.Window) void {
        // dock
        if (x11.getWindowProperty(self.display, w, atoms.net_wm_window_type, x11.XA_ATOM, x11.Atom)) |window_type|
            if (window_type == atoms.net_wm_window_type_dock) {
                self.addDockWindow(w);
                return;
            };

        // ordinary client
        var wa = std.mem.zeroes(x11.XWindowAttributes);
        if (x11.XGetWindowAttributes(self.display, w, &wa) == 0 or wa.override_redirect != 0) return;
        self.createClient(w);
    }

    fn createClient(self: *Self, w: x11.Window) void {
        // Update WM_STATE and visibility
        // TODO: move to MapRequest?
        const state = x11.getWindowWMState(self.display, w) orelse x11.WithdrawnState;
        var new_state = x11.NormalState;
        if (state == x11.WithdrawnState) {
            // Window is mapped for the first time
            // Choose its initial state according to ICCCM guidelines
            if (@ptrCast(?*x11.XWMHints, x11.XGetWMHints(self.display, w))) |wm_hints| {
                if (wm_hints.flags & x11.StateHint != 0 and wm_hints.initial_state == x11.IconicState)
                    new_state = x11.IconicState;
                _ = x11.XFree(wm_hints);
            }
        }
        if (state != x11.IconicState and new_state == x11.IconicState) {
            x11.hideWindow(self.display, w);
        } else if (state != x11.NormalState and new_state == x11.NormalState) {
            x11.unhideWindow(self.display, w);
        }

        if (self.findClientByWindow(w) != null) return;

        // Handle window type
        var w_trans: x11.Window = undefined;
        const is_transient = x11.XGetTransientForHint(self.display, w, &w_trans) != 0;
        const is_fullscreen =
            x11.getWindowProperty(self.display, w, atoms.net_wm_state, x11.XA_ATOM, x11.Atom) ==
            atoms.net_wm_state_fullscreen;
        const is_dialog =
            x11.getWindowProperty(self.display, w, atoms.net_wm_window_type, x11.XA_ATOM, x11.Atom) ==
            atoms.net_wm_window_type_dialog;
        const is_floating = is_transient or is_dialog;

        const new_node = self.clients.createNode();
        new_node.data = Client.init(w, self.display, is_floating, is_fullscreen);
        const c = &new_node.data;

        // Subscribe to events
        self.grabMouseButtons(c);
        _ = x11.XSelectInput(
            self.display,
            c.w,
            x11.EnterWindowMask,
        );

        // Add client
        var workspace_id: ?u8 = null;
        // Transient windows appear on the same workspace as their parents
        if (is_transient) {
            if (self.findClientByWindow(w_trans)) |c_trans|
                workspace_id = c_trans.workspace_id;
        }
        self.activeMonitor().addClient(c, workspace_id);

        log.info("Added client {}", .{w});
        log.trace("min_size ({}, {}), max_size ({}, {})", .{ c.min_size.x, c.min_size.y, c.max_size.x, c.max_size.y });
        if (is_transient) log.trace("window is transient", .{});
        if (is_dialog) log.trace("window is dialog", .{});
    }

    fn deleteClient(self: *Self, w: x11.Window) void {
        const node = self.findNodeByWindow(w) orelse unreachable;
        const client = &node.data;
        if (self.focused_client == client) self.focused_client = null;
        self.clients.destroyNode(node);
        log.info("Removed client {}", .{w});
    }

    fn findNodeByWindow(self: *Self, w: x11.Window) ?*ClientOwner.Node {
        var it = self.clients.list.first;
        while (it) |node| : (it = node.next)
            if (node.data.w == w) return node;
        return null;
    }

    fn findClientByWindow(self: *Self, w: x11.Window) ?*Client {
        if (self.findNodeByWindow(w)) |node| return &node.data;
        return null;
    }

    fn addDockWindow(self: *Self, w: x11.Window) void {
        if (self.dock_window != null) {
            log.err("Ignoring extra dock window {}", .{w});
            return;
        }

        log.info("Adding dock window {}", .{w});
        const C_Struts = extern struct {
            l: c_ulong = 0,
            r: c_ulong = 0,
            t: c_ulong = 0,
            b: c_ulong = 0,
        };
        var c_struts = x11.getWindowProperty(self.display, w, atoms.net_wm_strut_partial, x11.XA_CARDINAL, C_Struts);
        if (c_struts == null)
            c_struts = x11.getWindowProperty(self.display, w, atoms.net_wm_strut, x11.XA_CARDINAL, C_Struts);

        self.dock_struts = .{};
        if (c_struts) |struts|
            self.dock_struts = .{
                .left = @intCast(i32, struts.l),
                .right = @intCast(i32, struts.r),
                .top = @intCast(i32, struts.t),
                .bottom = @intCast(i32, struts.b),
            };

        var state = x11.getWindowWMState(self.display, w) orelse x11.WithdrawnState;
        if (state == x11.WithdrawnState) {
            state = x11.NormalState;
            x11.unhideWindow(self.display, w);
        }
        if (state == x11.IconicState) {
            self.applyStruts(.{});
        } else {
            self.applyStruts(self.dock_struts);
        }

        self.dock_window = w;
    }

    fn removeDockWindow(self: *Self) void {
        log.info("Removed dock window {?}", .{self.dock_window});
        self.dock_window = null;
        self.dock_struts = .{};
        self.applyStruts(.{});
    }

    fn applyStruts(self: *Self, struts: util.Struts) void {
        const screen = x11.XDefaultScreen(self.display);
        const m = self.activeMonitor();
        m.origin = Pos.init(0, 0);
        m.size = Size.init(
            x11.XDisplayWidth(self.display, screen),
            x11.XDisplayHeight(self.display, screen),
        );
        m.origin.x += struts.left;
        m.origin.y += struts.top;
        m.size.x -= struts.left + struts.right;
        m.size.y -= struts.top + struts.bottom;
        log.info("Applied struts {}", .{struts});

        self.markLayoutDirty();
    }

    fn grabMouseButtons(self: *Self, c: *Client) void {
        _ = x11.XUngrabButton(self.display, x11.AnyButton, x11.AnyModifier, c.w);
        if (c != self.focused_client) {
            // Focus unfocused clients on mouse button down event
            _ = x11.XGrabButton(
                self.display,
                x11.AnyButton,
                x11.AnyModifier,
                c.w,
                0,
                x11.ButtonPressMask,
                x11.GrabModeAsync,
                x11.GrabModeAsync,
                x11.None,
                x11.None,
            );
        }
        inline for (config.mouse_actions) |a|
            _ = x11.XGrabButton(
                self.display,
                a[2],
                a[1],
                c.w,
                0,
                x11.ButtonPressMask | x11.ButtonReleaseMask | x11.ButtonMotionMask,
                x11.GrabModeAsync,
                x11.GrabModeAsync,
                x11.None,
                x11.None,
            );
    }

    fn applyLayout(self: *Self) void {
        log.trace("Apply layout", .{});
        const mon_id = self.activeMonitor().id;
        const w_id = self.activeWorkspace().id;

        // Unhide clients belonging to the active workspace first, to minimize flickering
        var it = self.clients.list.first;
        while (it) |node| : (it = node.next) {
            const c = node.data;
            const visible = c.monitor_id == mon_id and c.workspace_id == w_id;
            if (visible and x11.getWindowWMState(self.display, c.w) != x11.NormalState)
                x11.unhideWindow(self.display, c.w);
        }

        self.activeMonitor().applyLayout(TileLayout);

        // Hide clients that are not on the active workspace
        it = self.clients.list.first;
        while (it) |node| : (it = node.next) {
            const c = node.data;
            const visible = c.monitor_id == mon_id and c.workspace_id == w_id;
            if (!visible and x11.getWindowWMState(self.display, c.w) == x11.NormalState)
                x11.hideWindow(self.display, c.w);
        }
        self.layout_dirty = false;

        // Skip EnterNotify events to avoid changing the focused window without delibarate mouse movement
        self.event_handler.skipEnterWindowEvents();
    }

    fn isAnotherWmDetected(d: *x11.Display, root: x11.Window) bool {
        const Checker = struct {
            var another_wm_detected = false;

            fn onWmDetected(_: ?*x11.Display, err: [*c]x11.XErrorEvent) callconv(.C) c_int {
                const e: *x11.XErrorEvent = err;
                std.debug.assert(e.error_code == x11.BadAccess);
                another_wm_detected = true;
                return 0;
            }
        };
        const defaultHandler = x11.XSetErrorHandler(Checker.onWmDetected);
        _ = x11.XSelectInput(d, root, x11.SubstructureRedirectMask);
        _ = x11.XSync(d, 0);
        _ = x11.XSetErrorHandler(defaultHandler);
        return Checker.another_wm_detected;
    }
};

const ErrorHandler = struct {
    var default_handler: x11.XErrorHandler = undefined;

    pub fn register() void {
        ErrorHandler.default_handler = x11.XSetErrorHandler(ErrorHandler.onXError);
    }

    pub fn deregister() void {
        _ = x11.XSetErrorHandler(ErrorHandler.default_handler);
    }

    fn onXError(d: ?*x11.Display, err: [*c]x11.XErrorEvent) callconv(.C) c_int {
        const e: *x11.XErrorEvent = err;
        var error_text: [1024:0]u8 = undefined;
        _ = x11.XGetErrorText(d, e.error_code, @ptrCast([*c]u8, &error_text), @sizeOf(@TypeOf(error_text)));
        log.err("ErrorEvent: request '{s}' xid {x}, error text '{s}'", .{
            x11.requestCodeToString(e.request_code) catch @panic("Unknown error request code"),
            e.resourceid,
            error_text,
        });
        return 0;
    }
};

const EventHandler = struct {
    const Self = @This();
    const MouseState = struct {
        start_pos: Pos = undefined,
        frame_pos: Pos = undefined,
        frame_size: Size = undefined,
        action: ?commands.MouseAction = null,
    };

    display: *x11.Display,
    wm: *Manager,
    mouse_state: MouseState = .{},

    fn init(d: *x11.Display, winMan: *Manager) EventHandler {
        return .{
            .display = d,
            .wm = winMan,
        };
    }

    fn deinit(self: *Self) void {
        _ = self;
    }

    fn processEvent(self: *Self) !void {
        var e = std.mem.zeroes(x11.XEvent);
        _ = x11.XNextEvent(self.display, &e);
        const ename = x11.eventTypeToString(@intCast(u8, e.type));
        try switch (e.type) {
            x11.UnmapNotify => self.onUnmapNotify(e.xunmap),
            x11.ConfigureNotify => {},
            x11.ConfigureRequest => self.onConfigureRequest(e.xconfigurerequest),
            x11.MapRequest => self.onMapRequest(e.xmaprequest),
            x11.ButtonPress => self.onButtonPress(e.xbutton),
            x11.ButtonRelease => self.onButtonRelease(e.xbutton),
            x11.MotionNotify => {
                while (x11.XCheckTypedWindowEvent(self.display, e.xmotion.window, x11.MotionNotify, &e) != 0) {}
                try self.onMotionNotify(e.xmotion);
            },
            x11.EnterNotify => self.onEnterNotify(e.xcrossing),
            x11.KeyPress => self.onKeyPress(e.xkey),
            x11.KeyRelease => self.onKeyRelease(e.xkey),
            x11.ClientMessage => self.onClientMessage(e.xclient),
            else => log.trace("ignored event {s}", .{ename}),
        };
    }

    fn skipEnterWindowEvents(self: *Self) void {
        var ev: x11.XEvent = undefined;
        _ = x11.XSync(self.display, 0);
        while (x11.XCheckMaskEvent(self.display, x11.EnterWindowMask, &ev) != 0) {}
    }

    fn onUnmapNotify(self: *Self, ev: x11.XUnmapEvent) !void {
        const w = ev.window;
        const wm = self.wm;
        log.trace("UnmapNotify for {}", .{w});
        if (wm.dock_window == w) {
            wm.removeDockWindow();
        } else if (wm.findClientByWindow(w)) |client| {
            // TODO: revisit with multi-monitor support; need to update layout for any active monitors
            const m = wm.activeMonitor();
            const need_update_layout = client.monitor_id == m.id and client.workspace_id == m.active_workspace_id;

            wm.activeMonitor().removeClient(client);
            wm.deleteClient(w);
            if (need_update_layout) wm.applyLayout();
            wm.updateFocus();
        } else {
            log.trace("skipping non-client window", .{});
            return;
        }

        x11.setWindowWMState(self.display, w, x11.WithdrawnState);
        // Remove _NET_WM_STATE when window goes into Withdrawn state (follow EWMH guidelines)
        _ = x11.XDeleteProperty(self.display, w, atoms.net_wm_state);
        _ = x11.XSync(self.display, 0);
    }

    fn onConfigureRequest(self: *Self, ev: x11.XConfigureRequestEvent) !void {
        var w = ev.window;
        log.trace("ConfigureRequest for {}", .{w});
        var changes = x11.XWindowChanges{
            .x = ev.x,
            .y = ev.y,
            .width = ev.width,
            .height = ev.height,
            .border_width = ev.border_width,
            .sibling = ev.above,
            .stack_mode = ev.detail,
        };
        if (self.wm.findClientByWindow(w)) |c| {
            if (c.is_fullscreen) {
                const m = self.wm.activeMonitor();
                changes.x = m.origin.x;
                changes.y = m.origin.y;
                changes.width = m.size.x;
                changes.height = m.size.y;
            }
        }
        _ = x11.XConfigureWindow(self.display, w, @intCast(c_uint, ev.value_mask), &changes);
        log.info("resize {} to ({}, {})", .{ w, changes.width, changes.height });
    }

    fn onMapRequest(self: *Self, ev: x11.XMapRequestEvent) void {
        const w = ev.window;
        log.trace("MapRequest for {}", .{w});

        self.wm.processNewWindow(w);
        self.wm.applyLayout();
        if (self.wm.activeClient() != self.wm.focused_client) self.wm.updateFocus();
    }

    fn onButtonPress(self: *Self, ev: x11.XButtonEvent) !void {
        log.trace("ButtonPress for {}", .{ev.window});
        const client = self.wm.findClientByWindow(ev.window) orelse @panic("Window is not a client");
        if (client != self.wm.focused_client) self.wm.focusClient(client);

        // Only floating clients can be moved/resized
        if (!client.is_floating) return;

        const mstate = &self.mouse_state;
        mstate.action = commands.firstMatchingMouseAction(config.mouse_actions, ev.button, ev.state);
        if (mstate.action != null) {
            const g = try client.getGeometry();
            mstate.start_pos = Pos.init(ev.x_root, ev.y_root);
            mstate.frame_pos = g.pos;
            mstate.frame_size = g.size;
        }
    }

    fn onButtonRelease(self: *Self, ev: x11.XButtonEvent) !void {
        log.trace("ButtonRelease for {}", .{ev.window});
        self.mouse_state.action = null;
    }

    fn onMotionNotify(self: *Self, ev: x11.XMotionEvent) !void {
        log.trace("MotionNotify for {}", .{ev.window});

        if (self.mouse_state.action == null) return;
        const mstate = &self.mouse_state;

        const drag_pos = Pos.init(ev.x_root, ev.y_root);
        const delta = vec.IntVec2.init(
            drag_pos.x - mstate.start_pos.x,
            drag_pos.y - mstate.start_pos.y,
        );

        const c = self.wm.findClientByWindow(ev.window) orelse @panic("Window is not a client");
        switch (mstate.action.?) {
            commands.MouseAction.Move => {
                const x = mstate.frame_pos.x + delta.x;
                const y = mstate.frame_pos.y + delta.y;
                log.info("Moving to ({}, {})", .{ x, y });
                _ = x11.XMoveWindow(self.display, c.w, x, y);
            },
            commands.MouseAction.Resize => {
                const w = @intCast(u32, std.math.clamp(
                    mstate.frame_size.x + delta.x,
                    c.min_size.x,
                    c.max_size.x,
                ));
                const h = @intCast(u32, std.math.clamp(
                    mstate.frame_size.y + delta.y,
                    c.min_size.y,
                    c.max_size.y,
                ));

                log.info("Resizing to ({}, {})", .{ w, h });
                _ = x11.XResizeWindow(self.display, ev.window, w, h);
            },
        }
    }

    fn onEnterNotify(self: *Self, ev: x11.XCrossingEvent) !void {
        log.trace("EnterNotify for {}", .{ev.window});
        const client = self.wm.findClientByWindow(ev.window) orelse @panic("Window is not a client");
        self.wm.focusClient(client);
    }

    fn sendEvent(self: *Self, w: x11.Window, protocol: x11.Atom) !void {
        var event = std.mem.zeroes(x11.XEvent);
        event.type = x11.ClientMessage;
        event.xclient.message_type = atoms.wm_protocols;
        event.xclient.window = w;
        event.xclient.format = 32;
        event.xclient.data.l[0] = @intCast(c_long, protocol);
        if (x11.XSendEvent(self.display, w, 0, x11.NoEventMask, &event) == 0) return error.Error;
    }

    fn killWindow(self: *Self, w: x11.Window) !void {
        var protocols: [*c]x11.Atom = null;
        var count: i32 = 0;
        _ = x11.XGetWMProtocols(self.display, w, &protocols, &count);
        defer _ = if (protocols != null) x11.XFree(protocols);

        var supports_delete = false;
        if (count > 0) {
            for (protocols[0..@intCast(usize, count)]) |p| {
                if (p == atoms.wm_delete) {
                    supports_delete = true;
                    break;
                }
            }
        }
        if (supports_delete) {
            log.info("Sending wm_delete to {}", .{w});
            try self.sendEvent(w, atoms.wm_delete);
        } else {
            log.info("Killing {}", .{w});
            _ = x11.XKillClient(self.display, w);
        }
    }

    fn onKeyPress(self: *Self, ev: x11.XKeyEvent) !void {
        inline for (config.key_actions) |a|
            if (ev.keycode == x11.XKeysymToKeycode(self.display, a[1]) and ev.state ^ a[0] == 0)
                @call(.{}, a[2], .{self.wm} ++ a[3]);
    }

    fn onKeyRelease(self: *Self, ev: x11.XKeyEvent) !void {
        _ = self;
        _ = ev;
    }

    fn onClientMessage(self: *Self, ev: x11.XClientMessageEvent) !void {
        log.trace("ClientMessage type {}", .{ev.message_type});
        if (ev.message_type == atoms.net_current_desktop) {
            // Dock is requesting to change the current desktop
            const id = @intCast(u8, ev.data.l[0]);
            if (id != self.wm.activeWorkspace().id) {
                log.trace("changing current desktop to {}", .{id});
                self.wm.focusWorkspace(id);
            }
        } else if (ev.message_type == atoms.net_wm_state) {
            const prop = ev.data.l[1];
            log.err("got net_wm_state message, prop = {}, fullscreen_prop = {}", .{ prop, atoms.net_wm_state_fullscreen });
            log.err("full prop = {any}", .{ev.data.l});
            if (prop == atoms.net_wm_state_fullscreen) {
                log.err("got net_wm_state_fullscreen message", .{});
                // Client wants to change its fullscreen state
                if (self.wm.findClientByWindow(ev.window)) |c| {
                    const net_wm_state_add = 1;
                    const net_wm_state_toggle = 2;
                    const action = ev.data.l[0];
                    const is_fullscreen = (action == net_wm_state_add or (action == net_wm_state_toggle and !c.is_fullscreen));
                    if (c.is_fullscreen != is_fullscreen) self.wm.setClientFullscreen(c, is_fullscreen);
                }
            }
        } else {
            log.trace("ignored ClientMessage event", .{});
        }
    }
};
