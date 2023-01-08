const std = @import("std");
const x11 = @import("x11.zig");
const log = @import("log.zig");
const config = @import("config.zig");
const commands = @import("commands.zig");
const util = @import("util.zig");
const clients_state = @import("clients_state.zig");
const atoms = @import("atoms.zig");
const Client = @import("client.zig").Client;
const TileLayout = @import("layout.zig").TileLayout;
const Workspace = @import("workspace.zig").Workspace;
const Monitor = @import("monitor.zig").Monitor;
const Pos = util.Pos;
const Size = util.Size;

const ClientFocus = enum {
    Focused,
    Unfocused,
};

pub const Manager = struct {
    const Self = @This();
    const ClientOwner = util.OwningList(Client);
    const root_event_mask = x11.SubstructureNotifyMask | x11.SubstructureRedirectMask | x11.StructureNotifyMask;
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
        x11.setWindowProperty(
            self.display,
            root,
            atoms.net_number_of_desktops,
            x11.XA_CARDINAL,
            @intCast(c_ulong, self.monitor.workspaces.len),
        );
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
        self.activateWorkspace(workspace_id);
        self.applyFocus(self.getFirstFocusNode(workspace_id));
    }

    /// Activate and switch focus to client.
    /// Also activate its monitor and workspace if they are not active.
    pub fn focusClient(self: *Self, client: *Client) void {
        if (client.workspace_id != self.activeWorkspace().id) self.activateWorkspace(client.workspace_id.?);
        self.applyFocus(self.findNodeByWindow(client.w));
    }

    /// Switch focus to the first client in the focus stack of the active workspace.
    pub fn updateFocus(self: *Self) void {
        self.applyFocus(self.getFirstFocusNode(self.activeWorkspace().id));
    }

    pub fn moveClientToWorkspace(self: *Self, client: *Client, monitor_id: u8, workspace_id: u8) void {
        std.debug.assert(monitor_id == 0); // TODO: change after implementing multi-monitor support
        if (client.monitor_id == monitor_id and client.workspace_id == workspace_id) return;

        // Will need to update layout and focus if moving to or from visible workspace.
        const visible_change = client.workspace_id == self.activeWorkspace().id or workspace_id == self.activeWorkspace().id;

        self.monitor.removeClient(client);
        self.monitor.addClient(client, workspace_id);
        if (visible_change) {
            self.applyLayout();
            self.updateFocus();
        }
        log.trace("Moved client {} to ({}, {})", .{ client.w, monitor_id, workspace_id });
    }

    pub fn markLayoutDirty(self: *Self) void {
        self.layout_dirty = true;
    }

    pub fn killClientWindow(self: *Self, client: *Client) void {
        self.event_handler.killWindow(client.w);
    }

    pub fn toggleDockWindow(self: *Self) void {
        if (self.dock_window) |w| {
            if (x11.getWindowWMState(self.display, w) == x11.NormalState) {
                x11.hideWindow(self.display, w);
            } else {
                x11.unhideWindow(self.display, w);
            }
            self.applyDockStruts();
        }
    }

    fn setClientFullscreen(self: *Self, c: *Client, is_fullscreen: bool) void {
        c.setFullscreenState(is_fullscreen);
        if (c.is_fullscreen) {
            const m = self.activeMonitor();
            c.moveResize(m.screen_origin, m.screen_size);
            self.markLayoutDirty();
            _ = x11.XRaiseWindow(self.display, c.w);
        } else {
            if (c.is_floating) {
                c.moveResize(c.pos, c.size);
            } else {
                self.markLayoutDirty();
            }
        }
    }

    fn getFirstFocusNode(self: *Self, workspace_id: u8) ?*ClientOwner.Node {
        var it = self.clients.list.first;
        while (it) |node| : (it = node.next) {
            if (node.data.workspace_id == workspace_id) return node;
        }
        return null;
    }

    fn activateWorkspace(self: *Self, workspace_id: u8) void {
        self.activeMonitor().activateWorkspace(workspace_id);
        self.applyLayout();

        x11.setWindowProperty(
            self.display,
            x11.XDefaultRootWindow(self.display),
            atoms.net_current_desktop,
            x11.XA_CARDINAL,
            @intCast(c_ulong, self.monitor.active_workspace_id),
        );
    }

    // If the client node is not null,
    //      move it to the front of the client list and switch focus to it.
    // Otherwise, reset focus to the root window.
    fn applyFocus(self: *Self, focusNode: ?*ClientOwner.Node) void {
        // Return early if the focus is not changing.
        if (focusNode) |n| if (self.focused_client == &n.data) return;
        if (self.focused_client == null and focusNode == null) return;

        // Remove focused state from the previously focused client.
        if (self.focused_client) |c| {
            c.setFocusedBorder(false);
            self.grabMouseButtons(c, ClientFocus.Unfocused);
        }

        if (focusNode) |n| {
            // Set focused state on the new client, grab mouse buttons, and move it to the front of the list.
            const c = &n.data;
            if (!c.is_fullscreen) c.setFocusedBorder(true);
            c.setInputFocus();
            self.grabMouseButtons(c, ClientFocus.Focused);
            if (c.is_floating)
                _ = x11.XRaiseWindow(self.display, c.w);
            self.clients.moveNodeToFront(n);
            self.focused_client = c;
            log.info("Focused client {}", .{c.w});
        } else {
            // Reset focus to root window.
            _ = x11.XSetInputFocus(self.display, x11.PointerRoot, x11.RevertToPointerRoot, x11.CurrentTime);
            self.focused_client = null;
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
                log.trace("Ignoring hidden {}", .{w});
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
        self.createClient(w, &wa);
    }

    fn createClient(self: *Self, w: x11.Window, wa: *x11.XWindowAttributes) void {
        if (self.findClientByWindow(w) == null) {
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

            // Pos, size
            var pos = Pos.init(wa.x, wa.y);
            var size = Pos.init(wa.width, wa.height);
            log.trace("WindowAttribtues for {}: x={}, y={}, width={}, height={}", .{
                w,
                wa.x,
                wa.y,
                wa.width,
                wa.height,
            });
            util.clipWindowPosSize(self.activeMonitor().origin, self.activeMonitor().size, &pos, &size);

            const new_node = self.clients.createNode();
            new_node.data = Client.init(w, self.display, pos, size, is_floating);
            const c = &new_node.data;

            // Subscribe to events
            self.grabMouseButtons(c, ClientFocus.Unfocused);
            _ = x11.XSelectInput(
                self.display,
                c.w,
                x11.EnterWindowMask | x11.PropertyChangeMask | x11.FocusChangeMask,
            );

            // Add client
            var workspace_id: ?u8 = null;
            // Transient windows appear on the same workspace as their parents
            if (is_transient) {
                if (self.findClientByWindow(w_trans)) |c_trans|
                    workspace_id = c_trans.workspace_id;
            }
            self.activeMonitor().addClient(c, workspace_id);

            if (is_fullscreen) self.setClientFullscreen(c, true);

            log.info("Added client {} with pos={}, size={}, is_floating={}, is_transient={}, is_dialog={}", .{
                w,
                pos,
                size,
                is_floating,
                is_transient,
                is_dialog,
            });
        }

        // TODO: move to MapRequest?
        const state = x11.getWindowWMState(self.display, w) orelse x11.WithdrawnState;
        var new_state = x11.NormalState;
        if (state == x11.WithdrawnState) {
            // Window is mapped for the first time
            // Choose its initial state according to ICCCM guidelines
            if (@ptrCast(?*x11.XWMHints, x11.XGetWMHints(self.display, w))) |wm_hints| {
                defer _ = x11.XFree(wm_hints);
                if (wm_hints.flags & x11.StateHint != 0 and wm_hints.initial_state == x11.IconicState)
                    new_state = x11.IconicState;
            }
        }
        if (state != x11.IconicState and new_state == x11.IconicState) {
            x11.hideWindow(self.display, w);
        } else if (state != x11.NormalState and new_state == x11.NormalState) {
            x11.unhideWindow(self.display, w);
        }
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

        const state = x11.getWindowWMState(self.display, w) orelse x11.WithdrawnState;
        if (state == x11.WithdrawnState) x11.unhideWindow(self.display, w);
        self.dock_window = w;
        self.applyDockStruts();
    }

    fn removeDockWindow(self: *Self) void {
        log.info("Removed dock window {?}", .{self.dock_window});
        self.dock_window = null;
        self.dock_struts = .{};
        self.applyDockStruts();
    }

    fn applyDockStruts(self: *Self) void {
        var struts = util.Struts{};
        if (self.dock_window) |w| {
            const state = x11.getWindowWMState(self.display, w);
            struts = if (state == x11.NormalState) self.dock_struts else .{};
        }
        self.monitor.applyStruts(struts);
        self.markLayoutDirty();
        log.info("Applied struts {}", .{struts});
    }

    fn setMonitorSize(self: *Self, size: Size) void {
        self.activeMonitor().screen_size = size;
        self.applyDockStruts();
        self.applyLayout();
        log.info("Set monitor size to {}", .{size});
    }

    // Instead of comparing with the focused client, receive focused state as an argument
    fn grabMouseButtons(self: *Self, c: *Client, client_focus: ClientFocus) void {
        _ = x11.XUngrabButton(self.display, x11.AnyButton, x11.AnyModifier, c.w);
        if (client_focus == .Unfocused) {
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
            x11.DestroyNotify => self.onDestroyNotify(e.xdestroywindow),
            x11.ConfigureNotify => self.onConfigureNotify(e.xconfigure),
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
            x11.PropertyNotify => self.onPropertyNotify(e.xproperty),
            x11.FocusIn => self.onFocusIn(e.xfocus),
            else => log.trace("ignored event {s}", .{ename}),
        };
    }

    fn skipEnterWindowEvents(self: *Self) void {
        var ev: x11.XEvent = undefined;
        _ = x11.XSync(self.display, 0);
        while (x11.XCheckMaskEvent(self.display, x11.EnterWindowMask, &ev) != 0) {}
    }

    fn unmanageWindow(self: *Self, w: x11.Window) !void {
        const wm = self.wm;
        if (wm.dock_window == w) {
            wm.removeDockWindow();
        } else if (wm.findClientByWindow(w)) |client| {
            // TODO: revisit with multi-monitor support; need to update layout for any active monitors
            const m = wm.activeMonitor();
            const removed_visible_client = client.monitor_id == m.id and client.workspace_id == m.active_workspace_id;
            wm.activeMonitor().removeClient(client);
            wm.deleteClient(w);
            if (removed_visible_client) {
                wm.applyLayout();
                wm.updateFocus();
            }
        } else {
            log.trace("skipping non-client window", .{});
            return;
        }

        x11.setWindowWMState(self.display, w, x11.WithdrawnState);
        // Remove _NET_WM_STATE when window goes into Withdrawn state (follow EWMH guidelines)
        _ = x11.XDeleteProperty(self.display, w, atoms.net_wm_state);
        _ = x11.XSync(self.display, 0);
    }

    fn onUnmapNotify(self: *Self, ev: x11.XUnmapEvent) !void {
        const w = ev.window;
        log.trace("UnmapNotify for {}", .{w});
        try self.unmanageWindow(w);
    }

    fn onDestroyNotify(self: *Self, ev: x11.XDestroyWindowEvent) !void {
        const w = ev.window;
        log.trace("DestroyNotify for {}", .{w});
        try self.unmanageWindow(w);
    }

    fn onConfigureRequest(self: *Self, ev: x11.XConfigureRequestEvent) !void {
        if (self.wm.findClientByWindow(ev.window)) |c| {
            log.trace("ConfigureRequest for client {}", .{c.w});
            const m = self.wm.activeMonitor();
            const bw: i32 = if (c.is_fullscreen) 0 else config.border.width;
            var ce = x11.XConfigureEvent{
                .type = x11.ConfigureNotify,
                .serial = 0,
                .send_event = 1,
                .display = self.display,
                .event = c.w,
                .window = c.w,
                .x = if (c.is_fullscreen) m.screen_origin.x else c.pos.x,
                .y = if (c.is_fullscreen) m.screen_origin.y else c.pos.y,
                .width = if (c.is_fullscreen) m.screen_size.x else c.size.x - 2 * bw,
                .height = if (c.is_fullscreen) m.screen_size.y else c.size.y - 2 * bw,
                .border_width = bw,
                .above = x11.None,
                .override_redirect = 0,
            };
            var send_event = true;
            if (c.is_floating and !c.is_fullscreen) {
                // Only a floating client that is not in fullscreen mode can be moved or resized
                var pos = c.pos;
                var size = c.size;
                if (ev.value_mask & x11.CWX != 0) pos.x = ev.x;
                if (ev.value_mask & x11.CWY != 0) pos.y = ev.y;
                if (ev.value_mask & x11.CWWidth != 0) size.x = ev.width + 2 * bw;
                if (ev.value_mask & x11.CWHeight != 0) size.y = ev.height + 2 * bw;
                c.moveResize(pos, size);
                // only send the event if x or y changed, but not width, height or border width (according to ICCCM guidelines)
                send_event = ev.value_mask & (x11.CWX | x11.CWY) != 0 and
                    ev.value_mask & (x11.CWWidth | x11.CWHeight | x11.CWBorderWidth) == 0;
                if (send_event) {
                    ce.x = c.pos.x;
                    ce.y = c.pos.y;
                    ce.width = size.x - 2 * bw;
                    ce.height = size.y - 2 * bw;
                }
            }
            if (send_event)
                _ = x11.XSendEvent(self.display, c.w, 0, x11.StructureNotifyMask, @ptrCast(*x11.XEvent, &ce));
        } else {
            var wc = x11.XWindowChanges{
                .x = ev.x,
                .y = ev.y,
                .width = ev.width,
                .height = ev.height,
                .border_width = ev.border_width,
                .sibling = ev.above,
                .stack_mode = ev.detail,
            };
            const value_mask = @intCast(c_uint, ev.value_mask);
            _ = x11.XConfigureWindow(self.display, ev.window, value_mask, &wc);
        }
    }

    fn onMapRequest(self: *Self, ev: x11.XMapRequestEvent) void {
        const w = ev.window;
        log.trace("MapRequest for {}", .{w});

        self.wm.processNewWindow(w);
        self.wm.applyLayout();
        self.wm.updateFocus();
    }

    fn onButtonPress(self: *Self, ev: x11.XButtonEvent) !void {
        log.trace("ButtonPress for {}", .{ev.window});
        const client = self.wm.findClientByWindow(ev.window) orelse @panic("Window is not a client");
        if (client != self.wm.focused_client) self.wm.focusClient(client);

        // Only floating clients can be moved/resized
        if (!client.is_floating or client.is_fullscreen) return;

        const mstate = &self.mouse_state;
        mstate.action = commands.firstMatchingMouseAction(config.mouse_actions, ev.button, ev.state);
        if (mstate.action != null) {
            mstate.start_pos = Pos.init(ev.x_root, ev.y_root);
            mstate.frame_pos = client.pos;
            mstate.frame_size = client.size;
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
        const delta = util.IntVec2.init(
            drag_pos.x - mstate.start_pos.x,
            drag_pos.y - mstate.start_pos.y,
        );

        const c = self.wm.findClientByWindow(ev.window) orelse @panic("Window is not a client");
        switch (mstate.action.?) {
            commands.MouseAction.Move => {
                var new_pos = mstate.frame_pos.addVec(delta);
                var size = c.size;
                util.clipWindowPosSize(self.wm.activeMonitor().origin, self.wm.activeMonitor().size, &new_pos, &size);
                c.move(new_pos);
                log.info("moved to ({}, {})", .{ c.pos.x, c.pos.y });
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
                var pos = c.pos;
                var new_size = Size.init(w, h);
                util.clipWindowPosSize(self.wm.activeMonitor().origin, self.wm.activeMonitor().size, &pos, &new_size);
                c.resize(new_size);
                log.info("resized to ({}, {})", .{ c.size.x, c.size.y });
            },
        }
    }

    fn onEnterNotify(self: *Self, ev: x11.XCrossingEvent) !void {
        log.trace("EnterNotify for {}", .{ev.window});
        const client = self.wm.findClientByWindow(ev.window) orelse @panic("Window is not a client");
        self.wm.focusClient(client);
    }

    fn killWindow(self: *Self, w: x11.Window) void {
        if (x11.windowParticipatesInProtocol(self.display, w, atoms.wm_delete)) {
            log.info("Sending wm_delete to {}", .{w});
            x11.sendProtocolEvent(self.display, w, atoms.wm_delete);
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

    fn onConfigureNotify(self: *Self, ev: x11.XConfigureEvent) !void {
        const root = x11.XDefaultRootWindow(self.display);
        if (root == ev.window) {
            self.wm.setMonitorSize(Size.init(ev.width, ev.height));
            log.info("ConfigureNotify for root window, new size: ({}, {})", .{ ev.width, ev.height });
        } else if (self.wm.findClientByWindow(ev.window)) |_| {
            log.trace("ConfgureNotify for client {} ignored", .{ev.window});
        }
    }

    fn onClientMessage(self: *Self, ev: x11.XClientMessageEvent) !void {
        var processed = false;
        var atom_name: [128]u8 = undefined;

        if (ev.message_type == atoms.net_current_desktop) {
            // Dock is requesting to change the current desktop
            log.trace("ClientMessage _NET_CURRENT_DESKTOP", .{});
            const id = @intCast(u8, ev.data.l[0]);
            if (id != self.wm.activeWorkspace().id) {
                log.trace("changing current desktop to {}", .{id});
                self.wm.focusWorkspace(id);
                processed = true;
            }
        } else if (ev.message_type == atoms.wm_change_state) {
            const state = ev.data.l[0];
            log.trace("ClientMessage WM_CHANGE_STATE with state {}", .{state});
        } else if (ev.message_type == atoms.net_wm_state) {
            const prop = ev.data.l[1];
            _ = x11.getAtomName(self.display, @intCast(c_ulong, prop), &atom_name);
            log.trace("ClientMessage _NET_WM_STATE with property {s} ({})", .{ atom_name, prop });
            if (prop == atoms.net_wm_state_fullscreen) {
                // Client wants to change its fullscreen state
                if (self.wm.findClientByWindow(ev.window)) |c| {
                    const net_wm_state_add = 1;
                    const net_wm_state_toggle = 2;
                    const action = ev.data.l[0];
                    const is_fullscreen = action == net_wm_state_add or
                        (action == net_wm_state_toggle and !c.is_fullscreen);
                    if (c.is_fullscreen != is_fullscreen)
                        self.wm.setClientFullscreen(c, is_fullscreen);
                    processed = true;
                }
            }
        }
        if (!processed) {
            _ = x11.getAtomName(self.display, ev.message_type, &atom_name);
            log.trace("ignored ClientMessage {s} ({})", .{ atom_name, ev.message_type });
        }
    }

    fn onPropertyNotify(self: *Self, ev: x11.XPropertyEvent) !void {
        const client = self.wm.findClientByWindow(ev.window) orelse return;

        var atom_name: [128]u8 = undefined;
        _ = x11.getAtomName(self.display, ev.atom, &atom_name);
        log.trace("PropertyNotify for {} with property {s} ({})", .{ ev.window, atom_name, ev.atom });

        switch (ev.atom) {
            x11.XA_WM_HINTS => client.updateWMHints(),
            x11.XA_WM_NORMAL_HINTS => client.updateWMNormalHints(),
            else => {},
        }
    }

    fn onFocusIn(self: *Self, ev: x11.XFocusChangeEvent) !void {
        const c = self.wm.findClientByWindow(ev.window) orelse return;
        if (self.wm.focused_client == c) return;

        // Return focus to the currenly focused client.
        c.setInputFocus();
    }
};
