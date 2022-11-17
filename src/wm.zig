const std = @import("std");
const x11 = @import("x11.zig");
const log = @import("log.zig");
const config = @import("config.zig");
const commands = @import("commands.zig");
const util = @import("util.zig");
const clients_state = @import("clients_state.zig");
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
    var is_instance_alive = false;

    display: *x11.Display = undefined,
    clients: ClientOwner = undefined,
    event_handler: EventHandler = undefined,
    monitor: Monitor = undefined,
    focused_client: ?*Client = null,
    layout_dirty: bool = false,
    exit_code: ?u8 = null,
    state_file: ?[]const u8 = null,

    pub fn deinit(self: *Self) void {
        if (!is_instance_alive) return;

        if (self.state_file) |file| {
            log.info("Saving state to {s}", .{file});
            clients_state.saveState(self, file) catch |e| {
                log.err("Cannot save clients state, error {}", .{e});
            };
        }

        self.monitor.deinit();
        self.event_handler.deinit();
        const root = x11.XDefaultRootWindow(self.display);
        _ = x11.XUngrabKey(self.display, x11.AnyKey, x11.AnyModifier, root);
        _ = x11.XCloseDisplay(self.display);
        ErrorHandler.deregister();
        is_instance_alive = false;
        log.info("Destroyed wm", .{});
    }

    pub fn run(self: *Self, display_name_arg: ?[:0]const u8, state_file_arg: ?[]const u8) !u8 {
        if (is_instance_alive) return error.WmInstanceAlreadyExists;
        const display_name: [:0]const u8 = if (display_name_arg) |name| name else ":0";
        const display = x11.XOpenDisplay(@ptrCast([*c]const u8, display_name)) orelse return error.CannotOpenDisplay;
        const root = x11.XDefaultRootWindow(display);
        if (isAnotherWmDetected(display, root)) return error.AnotherWmDetected;
        ErrorHandler.register();

        is_instance_alive = true;
        self.display = display;
        self.clients = ClientOwner.init();
        self.event_handler = EventHandler.init(display, self);
        const screen = x11.XDefaultScreen(display);
        self.monitor = Monitor.init(
            Size.init(
                x11.XDisplayWidth(display, screen),
                x11.XDisplayHeight(display, screen),
            ),
        );
        self.manageExistingWindows();
        var wa = std.mem.zeroes(x11.XSetWindowAttributes);
        // show cursor
        wa.cursor = x11.XCreateFontCursor(self.display, x11.XC_left_ptr);
        // select events
        wa.event_mask = x11.SubstructureNotifyMask | x11.SubstructureRedirectMask;
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
        self.updateFocus(false);
        self.markLayoutDirty();
    }

    pub fn activeClient(self: *Self) ?*Client {
        return self.activeWorkspace().active_client;
    }

    /// Activate and switch focus to client.
    /// Also activate its monitor and workspace if they are not active.
    pub fn focusClient(self: *Self, client: *Client) void {
        // TODO: revisit for multi-monitor support
        if (client.workspace_id.? != self.activeWorkspace().id) {
            self.activeMonitor().activateWorkspace(client.workspace_id.?);
            self.markLayoutDirty();
        }
        self.activeWorkspace().activateClient(client);
        self.updateFocus(false);
    }

    pub fn focusNextClient(self: *Self) void {
        const w = self.activeWorkspace();
        std.debug.assert(self.focused_client != null);
        std.debug.assert(w.active_client == self.focused_client.?);
        w.activateNextClient();
        self.updateFocus(false);
    }

    pub fn focusPrevClient(self: *Self) void {
        const w = self.activeWorkspace();
        std.debug.assert(self.focused_client != null);
        std.debug.assert(w.active_client == self.focused_client.?);
        w.activatePrevClient();
        self.updateFocus(false);
    }

    pub fn moveClientToWorkspace(self: *Self, client: *Client, monitor_id: u8, workspace_id: u8) void {
        std.debug.assert(monitor_id == 0); // TODO: change after implementing multi-monitor support
        if (client.monitor_id == monitor_id and client.workspace_id == workspace_id) return;
        self.monitor.removeClient(client);
        self.monitor.addClient(client, workspace_id);
        self.updateFocus(false);
        self.markLayoutDirty();
    }

    pub fn markLayoutDirty(self: *Self) void {
        self.layout_dirty = true;
    }

    pub fn killClientWindow(self: *Self, client: *Client) void {
        self.event_handler.killWindow(client.w) catch unreachable;
    }

    /// Switch focus to the active client of the active workspace of the active monitor.
    /// Do nothing if client is already focused, unless forceUpdate is true.
    fn updateFocus(self: *Self, forceUpdate: bool) void {
        const client = self.activeClient();
        if (!forceUpdate and self.focused_client == client) return;

        const prev_focused_client = self.focused_client;
        self.focused_client = client;

        if (prev_focused_client) |c| {
            c.setFocusedBorder(false);
            self.grabMouseButtons(c);
        }

        if (client) |c| {
            // update border state and grab focus
            c.setFocusedBorder(true);
            _ = x11.XSetInputFocus(self.display, c.w, x11.RevertToPointerRoot, x11.CurrentTime);
            _ = x11.XRaiseWindow(self.display, c.w);
            self.grabMouseButtons(c);
            log.info("Focused client {}", .{c.w});
        } else {
            // reset focus
            _ = x11.XSetInputFocus(self.display, x11.PointerRoot, x11.RevertToPointerRoot, x11.CurrentTime);
            log.info("Cleared focus", .{});
        }
    }

    fn manageExistingWindows(self: *Self) void {
        const root = x11.XDefaultRootWindow(self.display);
        var root_ret: x11.Window = undefined;
        var parent: x11.Window = undefined;
        var ws: [*c]x11.Window = null;
        var nws: c_uint = 0;
        _ = x11.XQueryTree(self.display, root, &root_ret, &parent, &ws, &nws);
        defer _ = if (ws != null) x11.XFree(ws);
        if (nws > 0) for (ws[0..nws]) |w| {
            var wa = std.mem.zeroes(x11.XWindowAttributes);
            if (x11.XGetWindowAttributes(self.display, w, &wa) == 0) {
                log.err("XGetWindowAttributes failed for {}", .{w});
                continue;
            }
            // Only add windows that are visible and don't set override_redirect
            if (wa.override_redirect == 0 and wa.map_state == x11.IsViewable) {
                const c = self.createClient(w) catch unreachable;
                self.activeMonitor().addClient(c, null);
            } else {
                log.info("Ignoring {}", .{w});
            }
        };
        self.updateFocus(true);
        self.markLayoutDirty();
    }

    fn createClient(self: *Self, w: x11.Window) !*Client {
        if (self.findClientByWindow(w) != null) return error.WindowAlreadyManaged;

        var wa = std.mem.zeroes(x11.XWindowAttributes);
        if (x11.XGetWindowAttributes(self.display, w, &wa) == 0) unreachable;
        _ = x11.XSelectInput(
            self.display,
            w,
            x11.EnterWindowMask,
        );

        const new_node = self.clients.createNode();
        new_node.data = Client.init(w, self.display);
        const c = &new_node.data;
        self.grabMouseButtons(c);
        log.info("Added client {}", .{w});
        log.trace("min_size ({}, {}), max_size ({}, {})", .{ c.min_size.x, c.min_size.y, c.max_size.x, c.max_size.y });
        return c;
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

        self.activeMonitor().applyLayout(TileLayout);
        // TODO: figure out a more elegant solution?
        const mon_id = self.activeMonitor().id;
        const w_id = self.activeWorkspace().id;
        var it = self.clients.list.first;
        while (it) |node| : (it = node.next) {
            const c = node.data;
            if (c.monitor_id != mon_id or c.workspace_id != w_id) {
                node.data.move(.{ .x = -10000, .y = -10000 });
            }
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
    wm_delete: x11.Atom = undefined,
    wm_protocols: x11.Atom = undefined,
    mouse_state: MouseState = .{},

    fn init(d: *x11.Display, winMan: *Manager) EventHandler {
        return .{
            .display = d,
            .wm = winMan,
            .wm_delete = x11.XInternAtom(d, "WM_DELETE_WINDOW", 0),
            .wm_protocols = x11.XInternAtom(d, "WM_PROTOCOLS", 0),
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
            else => log.trace("ignored event {s}", .{ename}),
        };
    }

    fn skipEnterWindowEvents(self: *Self) void {
        var ev: x11.XEvent = undefined;
        _ = x11.XSync(self.display, 0);
        while (x11.XCheckMaskEvent(self.display, x11.EnterWindowMask, &ev) != 0) {}
    }

    fn onUnmapNotify(self: *Self, ev: x11.XUnmapEvent) !void {
        log.trace("UnmapNotify for {}", .{ev.window});
        const wm = self.wm;
        if (wm.findClientByWindow(ev.window)) |client| {
            // TODO: revisit with multi-monitor support; need to update layout for any active monitors
            const m = wm.activeMonitor();
            const need_update_layout = client.monitor_id == m.id and client.workspace_id == m.active_workspace_id;
            if (need_update_layout) wm.markLayoutDirty();

            wm.activeMonitor().removeClient(client);
            wm.deleteClient(ev.window);
            wm.updateFocus(true);
        } else {
            log.trace("skipping non-client window", .{});
        }
    }

    fn onConfigureRequest(self: *Self, ev: x11.XConfigureRequestEvent) !void {
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
        _ = x11.XConfigureWindow(self.display, w, @intCast(c_uint, ev.value_mask), &changes);
        log.info("resize {} to ({}, {})", .{ w, changes.width, changes.height });
    }

    fn onMapRequest(self: *Self, ev: x11.XMapRequestEvent) void {
        const w = ev.window;
        log.trace("MapRequest for {}", .{w});
        _ = x11.XMapWindow(self.display, w);
        const c = self.wm.createClient(w) catch |e| {
            log.err("error {}", .{e});
            return;
        };
        self.wm.activeMonitor().addClient(c, null);
        self.wm.updateFocus(false);
        self.wm.markLayoutDirty();
    }

    fn onButtonPress(self: *Self, ev: x11.XButtonEvent) !void {
        log.trace("ButtonPress for {}", .{ev.window});
        const client = self.wm.findClientByWindow(ev.window) orelse @panic("Window is not a client");
        if (client != self.wm.focused_client) self.wm.focusClient(client);

        const mstate = &self.mouse_state;
        mstate.action = commands.firstMatchingMouseAction(config.mouse_actions, ev.button, ev.state) orelse null;
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
        event.xclient.message_type = self.wm_protocols;
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
                if (p == self.wm_delete) {
                    supports_delete = true;
                    break;
                }
            }
        }
        if (supports_delete) {
            log.info("Sending wm_delete to {}", .{w});
            try self.sendEvent(w, self.wm_delete);
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
};
