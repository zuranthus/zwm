// TODO - cleanup
// TODO - move hotkeys funcs to WM/make WM hotkey API class?
// TODO - extract layout
// TODO - move classes around
// TODO - how to focus? how to change tags?
const std = @import("std");
const x11 = @import("x11.zig");
const log = @import("log.zig");
const hotkeys = @import("hotkeys.zig");
const util = @import("util.zig");
const client_import = @import("client.zig");
const Client = client_import.Client;
const TileLayout = @import("layout.zig").TileLayout;

const vec = @import("vec.zig");
const Pos = vec.Pos;
const Size = vec.Size;

const DragState = struct {
    start_pos: Pos,
    frame_pos: Pos,
    frame_size: Size,
};



const workspaceCount: u8 = 10;

pub const Workspace = struct {
    const Self = @This();
    const Clients = std.ArrayList(*Client);

    id: u8,
    clients: Clients,
    activeClient: ?*Client = null,

    pub fn init(workspaceId: u8) Self {
        return .{ .id = workspaceId, .clients = Clients.init(std.heap.c_allocator) };
    }

    pub fn deinit(self: *Self) void {
        self.clients.deinit();
    }

    pub fn addClient(self: *Self, client: *Client) void {
        std.debug.assert(client.workspaceId != self.id);
        client.workspaceId = self.id;
        self.clients.insert(0, client) catch @panic("");
        self.activeClient = client;
    }

    pub fn activateClient(self: *Self, client: *Client) void {
        if (!util.contains(self.clients.items, client)) @panic("Client is not part of the workspace");
        self.activeClient = client;
    }

    pub fn activateNextClient(self: *Self) void {
        if (self.activeClient) |client| {
            const i = util.findIndex(self.clients.items, client).?;
            const nextIndex = util.nextIndex(self.clients.items, i);
            self.activeClient = self.clients.items[nextIndex];
        }
    }

    pub fn activatePrevClient(self: *Self) void {
        if (self.activeClient) |client| {
            const i = util.findIndex(self.clients.items, client).?;
            const prevIndex = util.prevIndex(self.clients.items, i);
            self.activeClient = self.clients.items[prevIndex];
        }
    }

    pub fn swapWithNextClient(self: *Self, client: *Client) *Client {
        const i = util.findIndex(self.clients.items, client).?;
        const nextIndex = util.nextIndex(self.clients.items, i);
        util.swap(self.clients.items, i, nextIndex);
        return self.clients.items[i];
    }

    pub fn swapWithPrevClient(self: *Self, client: *Client) *Client {
        const i = util.findIndex(self.clients.items, client).?;
        const prevIndex = util.prevIndex(self.clients.items, i);
        util.swap(self.clients.items, i, prevIndex);
        return self.clients.items[i];
    }

    pub fn swapWithFirst(self: *Self, client: *Client) *Client {
        const i = util.findIndex(self.clients.items, client).?;
        util.swap(self.clients.items, i, 0);
        return self.clients.items[i];
    }

    pub fn removeClient(self: *Self, client: *Client) bool {
        if (util.findIndex(self.clients.items, client)) |i| {
            const c = self.clients.orderedRemove(i);
            std.debug.assert(client == c);
            client.workspaceId = null;
            if (client == self.activeClient) {
                // activate next client if the removed was active
                // or activate the last client if the removed active client was last
                const len = self.clients.items.len;
                if (len == 0) {
                    self.activeClient = null;
                } else {
                    self.activeClient = self.clients.items[if (i == len) len - 1 else i];
                }
            }
            return true;
        }
        return false;
    }
};

pub const Monitor = struct {
    const Self = @This();

    size: Size,
    mainSize: f32 = 50.0,
    workspaces: [workspaceCount]Workspace = undefined,
    activeWorkspaceIndex: u8 = 1,

    pub fn init(monitorSize: Size) Self {
        var m = Self{ .size = monitorSize };
        for (m.workspaces) |*w, i| w.* = Workspace.init(@intCast(u8, i));
        return m;
    }

    pub fn deinit(self: *Monitor) void {
        for (self.workspaces) |*w| w.deinit();
    }

    pub fn activateWorkspace(self: *Self, workspaceIndex: u8) void {
        // TODO: allow 0?
        std.debug.assert(1 <= workspaceIndex and workspaceIndex <= workspaceCount);
        self.activeWorkspaceIndex = workspaceIndex;
    }

    pub fn activeWorkspace(self: *Self) *Workspace {
        return &self.workspaces[self.activeWorkspaceIndex];
    }

    pub fn addClient(self: *@This(), client: *Client, workspaceId: ?u8) void {
        std.debug.assert(client.monitorId == null or client.monitorId.? != 0);
        client.monitorId = 0; // TODO: replace with current monitor's id
        const workspace = if (workspaceId) |id| &self.workspaces[id] else self.activeWorkspace();
        workspace.addClient(client);
    }

    pub fn removeClient(self: *@This(), client: *Client) void {
        for (self.workspaces) |*w|
            if (w.removeClient(client)) {
                client.monitorId = null;
            };
    }

    pub fn applyLayout(self: *@This(), layout: anytype) void {
        layout.apply(self.activeWorkspace().clients.items, Pos.init(0, 0), self.size, self.mainSize / 100.0);
    }
};

const ErrorHandler = struct {
    var defaultHandler: x11.XErrorHandler = undefined;

    pub fn register() void {
        ErrorHandler.defaultHandler = x11.XSetErrorHandler(ErrorHandler.onXError);
    }

    pub fn deregister() void {
        _ = x11.XSetErrorHandler(ErrorHandler.defaultHandler);
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

    display: *x11.Display,
    wm: *Manager,
    wm_delete: x11.Atom = undefined,
    wm_protocols: x11.Atom = undefined,
    dragState: ?DragState = null,

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
        const client = self.wm.findClientByWindow(ev.window) orelse @panic("Window is not a client");
        self.wm.activeMonitor().removeClient(client);
        self.wm.deleteClient(ev.window);
        self.wm.updateFocus(true);
        self.wm.markLayoutDirty();
    }

    fn onConfigureRequest(m: *Self, ev: x11.XConfigureRequestEvent) !void {
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
        _ = x11.XConfigureWindow(m.display, w, @intCast(c_uint, ev.value_mask), &changes);
        log.info("resize {} to ({}, {})", .{ w, changes.width, changes.height });
    }

    fn onMapRequest(self: *Self, ev: x11.XMapRequestEvent) void {
        const w = ev.window;
        log.trace("MapRequest for {}", .{w});
        _ = x11.XMapWindow(self.display, w);
        const c = self.wm.createClient(w);
        self.wm.activeMonitor().addClient(c, null);
        self.wm.updateFocus(false);
        self.wm.markLayoutDirty();
    }

    fn onButtonPress(self: *Self, ev: x11.XButtonEvent) !void {
        log.trace("ButtonPress for {}", .{ev.window});
        const client = self.wm.findClientByWindow(ev.window) orelse @panic("Window is not a client");
        const g = try client.getGeometry();
        self.dragState = DragState{
            .start_pos = Pos.init(ev.x_root, ev.y_root),
            .frame_pos = g.pos,
            .frame_size = g.size,
        };
        _ = x11.XRaiseWindow(self.display, client.w);
    }

    fn onButtonRelease(self: *Self, ev: x11.XButtonEvent) !void {
        _ = ev;
        self.dragState = null;
    }

    fn onMotionNotify(self: *Self, ev: x11.XMotionEvent) !void {
        log.trace("MotionNotify for {}", .{ev.window});
        if (self.dragState == null) return;
        const drag = self.dragState.?;

        const c = self.wm.findClientByWindow(ev.window) orelse @panic("Window is not a client");
        const drag_pos = Pos.init(ev.x_root, ev.y_root);
        const delta = vec.IntVec2.init(
            drag_pos.x - drag.start_pos.x,
            drag_pos.y - drag.start_pos.y,
        );

        if (ev.state & x11.Button1Mask != 0) {
            const x = drag.frame_pos.x + delta.x;
            const y = drag.frame_pos.y + delta.y;
            log.info("Moving to ({}, {})", .{ x, y });
            _ = x11.XMoveWindow(self.display, c.w, x, y);
        } else if (ev.state & x11.Button3Mask != 0) {
            const w = @intCast(u32, std.math.clamp(
                drag.frame_size.x + delta.x,
                c.min_size.x,
                c.max_size.x,
            ));
            const h = @intCast(u32, std.math.clamp(
                drag.frame_size.y + delta.y,
                c.min_size.y,
                c.max_size.y,
            ));

            log.info("Resizing to ({}, {})", .{ w, h });
            _ = x11.XResizeWindow(self.display, ev.window, w, h);
        }
    }

    fn onEnterNotify(self: *Self, ev: x11.XCrossingEvent) !void {
        log.trace("EnterNotify for {}", .{ev.window});
        if (ev.mode != x11.NotifyNormal or ev.detail == x11.NotifyInferior) return;
        const client = self.wm.findClientByWindow(ev.window) orelse @panic("Window is not a client");
        self.wm.activateClient(client);
        self.wm.updateFocus(false);
    }

    fn sendEvent(m: *Self, w: x11.Window, protocol: x11.Atom) !void {
        var event = std.mem.zeroes(x11.XEvent);
        event.type = x11.ClientMessage;
        event.xclient.message_type = m.wm_protocols;
        event.xclient.window = w;
        event.xclient.format = 32;
        event.xclient.data.l[0] = @intCast(c_long, protocol);
        if (x11.XSendEvent(m.display, w, 0, x11.NoEventMask, &event) == 0) return error.Error;
    }

    fn killWindow(self: *Self, w: x11.Window) !void {
        var protocols: [*c]x11.Atom = null;
        var count: i32 = 0;
        _ = x11.XGetWMProtocols(self.display, w, &protocols, &count);
        defer _ = if (protocols != null) x11.XFree(protocols);

        var supportsDelete = false;
        if (count > 0) {
            for (protocols[0..@intCast(usize, count)]) |p| {
                if (p == self.wm_delete) {
                    supportsDelete = true;
                    break;
                }
            }
        }
        if (supportsDelete) {
            log.info("Sending wm_delete to {}", .{w});
            try self.sendEvent(w, self.wm_delete);
        } else {
            log.info("Killing {}", .{w});
            _ = x11.XKillClient(self.display, w);
        }
    }

    fn onKeyPress(m: *Self, ev: x11.XKeyEvent) !void {
        // TODO extract?
        inline for (hotkeys.hotkeys) |hk|
            if (ev.keycode == x11.XKeysymToKeycode(m.display, hk[1]) and ev.state ^ hk[0] == 0)
                @call(.{}, hk[2], .{m.wm} ++ hk[3]);
    }

    fn onKeyRelease(m: *Self, ev: x11.XKeyEvent) !void {
        _ = m;
        _ = ev;
    }
};

pub const ClientsOwner = struct {
    const Self = @This();
    const Clients = std.SinglyLinkedList(Client);
    const Node = Clients.Node;

    clients: Clients = Clients{},

    pub fn init() Self {
        return .{};
    }

    pub fn deinit(self: *Self) void {
        var it = self.clients.first;
        while (it) |node| : (it = node.next) std.heap.c_allocator.destroy(node);
        self.clients = .{};
    }

    pub fn createNode(self: *Self) *Node {
        const newNode = std.heap.c_allocator.create(Node) catch unreachable;
        self.clients.prepend(newNode);
        return newNode;
    }

    pub fn destroyNode(self: *Self, node: *Node) void {
        self.clients.remove(node);
        std.heap.c_allocator.destroy(node);
    }

    fn findClientNodeByWindow(self: *Self, w: x11.Window) ?*Node {
        var it = self.clients.first;
        while (it) |node| : (it = node.next)
            if (node.data.w == w) return node;
        return null;
    }
};

pub const Manager = struct {
    const Self = @This();
    var isInstanceAlive = false;
    const modKey = x11.Mod1Mask;

    display: *x11.Display = undefined,
    clients: ClientsOwner = undefined,
    eventHandler: EventHandler = undefined,
    monitor: Monitor = undefined,
    focusedClient: ?*Client = null,
    layoutDirty: bool = false,

    fn isAnotherWmDetected(d: *x11.Display, root: x11.Window) bool {
        const Checker = struct {
            var anotherWmDetected = false;

            fn onWmDetected(_: ?*x11.Display, err: [*c]x11.XErrorEvent) callconv(.C) c_int {
                const e: *x11.XErrorEvent = err;
                std.debug.assert(e.error_code == x11.BadAccess);
                anotherWmDetected = true;
                return 0;
            }
        };
        const defaultHandler = x11.XSetErrorHandler(Checker.onWmDetected);
        _ = x11.XSelectInput(d, root, x11.SubstructureRedirectMask | x11.SubstructureNotifyMask);
        _ = x11.XSync(d, 0);
        _ = x11.XSetErrorHandler(defaultHandler);
        return Checker.anotherWmDetected;
    }

    pub fn init(m: *Manager) !void {
        if (isInstanceAlive) return error.WmInstanceAlreadyExists;
        const display = x11.XOpenDisplay(":1") orelse return error.CannotOpenDisplay;
        const root = x11.XDefaultRootWindow(display);
        if (isAnotherWmDetected(display, root)) return error.AnotherWmDetected;
        ErrorHandler.register();

        isInstanceAlive = true;
        m.display = display;
        m.clients = ClientsOwner.init();
        m.eventHandler = EventHandler.init(display, m);
        const screen = x11.XDefaultScreen(display);
        m.monitor = Monitor.init(
            Size.init(
                x11.XDisplayWidth(display, screen),
                x11.XDisplayHeight(display, screen),
            ),
        );
    }

    pub fn deinit(self: *Manager) void {
        std.debug.assert(isInstanceAlive);
        self.monitor.deinit();
        self.eventHandler.deinit();
        const root = x11.XDefaultRootWindow(self.display);
        _ = x11.XUngrabKey(self.display, x11.AnyKey, x11.AnyModifier, root);
        _ = x11.XCloseDisplay(self.display);
        ErrorHandler.deregister();
        isInstanceAlive = false;
        log.info("destroyed wm", .{});
    }

    pub fn run(m: *Manager) !void {
        m.initWm();
        try m.startEventLoop();
    }

    fn initWm(m: *Manager) void {
        // manage existing visbile windows
        m.manageExistingWindows();

        const root = x11.XDefaultRootWindow(m.display);
        // show cursor
        var wa = std.mem.zeroes(x11.XSetWindowAttributes);
        wa.cursor = x11.XCreateFontCursor(m.display, x11.XC_left_ptr);
        _ = x11.XChangeWindowAttributes(m.display, root, x11.CWCursor, &wa);
        // hotkeys
        // TODO extract?
        _ = x11.XUngrabKey(m.display, x11.AnyKey, x11.AnyModifier, root);
        inline for (hotkeys.hotkeys) |hk|
            _ = x11.XGrabKey(
                m.display,
                x11.XKeysymToKeycode(m.display, hk[1]),
                hk[0],
                root,
                0,
                x11.GrabModeAsync,
                x11.GrabModeAsync,
            );

        log.info("initialized wm", .{});
    }

    fn manageExistingWindows(m: *Manager) void {
        const root = x11.XDefaultRootWindow(m.display);
        var rootRet: x11.Window = undefined;
        var parent: x11.Window = undefined;
        var ws: [*c]x11.Window = null;
        var nws: c_uint = 0;
        _ = x11.XQueryTree(m.display, root, &rootRet, &parent, &ws, &nws);
        defer _ = if (ws != null) x11.XFree(ws);
        if (nws > 0) for (ws[0..nws]) |w| {
            var wa = std.mem.zeroes(x11.XWindowAttributes);
            if (x11.XGetWindowAttributes(m.display, w, &wa) == 0) {
                log.err("XGetWindowAttributes failed for {}", .{w});
                continue;
            }
            // Only add windows that are visible and don't set override_redirect
            if (wa.override_redirect == 0 and wa.map_state == x11.IsViewable) {
                const c = m.createClient(w);
                m.activeMonitor().addClient(c, null);
            } else {
                log.info("Ignoring {}", .{w});
            }
        };
        m.updateFocus(true);
        m.markLayoutDirty();
    }

    fn startEventLoop(m: *Manager) !void {
        while (true) {
            if (m.layoutDirty) m.applyLayout();
            try m.eventHandler.processEvent();
        }
    }

    fn createClient(self: *Self, w: x11.Window) *Client {
        std.debug.assert(self.findClientByWindow(w) == null);
        var wa = std.mem.zeroes(x11.XWindowAttributes);
        if (x11.XGetWindowAttributes(self.display, w, &wa) == 0) unreachable;
        _ = x11.XSelectInput(
            self.display,
            w,
            x11.EnterWindowMask | x11.SubstructureRedirectMask | x11.SubstructureNotifyMask,
        );
        // move with mod + LB
        _ = x11.XGrabButton(
            self.display,
            x11.Button1,
            modKey,
            w,
            0,
            x11.ButtonPressMask | x11.ButtonReleaseMask | x11.ButtonMotionMask,
            x11.GrabModeAsync,
            x11.GrabModeAsync,
            x11.None,
            x11.None,
        );
        // resize with mod + RB
        _ = x11.XGrabButton(
            self.display,
            x11.Button3,
            modKey,
            w,
            0,
            x11.ButtonPressMask | x11.ButtonReleaseMask | x11.ButtonMotionMask,
            x11.GrabModeAsync,
            x11.GrabModeAsync,
            x11.None,
            x11.None,
        );
        const newNode = self.clients.createNode();
        newNode.data = Client.init(w, self.display);
        const c = &newNode.data;
        log.info("Added client {}", .{w});
        log.trace("min_size ({}, {}), max_size ({}, {})", .{ c.min_size.x, c.min_size.y, c.max_size.x, c.max_size.y });
        return c;
    }

    fn findClientByWindow(self: *Manager, w: x11.Window) ?*Client {
        return if (self.clients.findClientNodeByWindow(w)) |node| &node.data else null;
    }

    fn deleteClient(self: *Manager, w: x11.Window) void {
        const node = self.clients.findClientNodeByWindow(w) orelse unreachable;
        const client = &node.data;
        if (self.focusedClient == client) self.focusedClient = null;
        self.clients.destroyNode(node);
        log.info("Removed client {}", .{w});
    }

    pub fn activeMonitor(self: *Manager) *Monitor {
        return &self.monitor;
    }

    pub fn activeWorkspace(self: *Manager) *Workspace {
        return self.activeMonitor().activeWorkspace();
    }

    pub fn activateWorkspace(self: *Manager, workspaceId: u8) void {
        self.activeMonitor().activateWorkspace(workspaceId);
    }

    fn activeClient(self: *Manager) ?*Client {
        return self.activeWorkspace().activeClient;
    }

    pub fn activateClient(self: *Manager, client: *Client) void {
        self.activeWorkspace().activateClient(client);
    }

    pub fn moveClientToWorkspace(self: *Manager, client: *Client, monitorId: u8, workspaceId: u8) void {
        std.debug.assert(monitorId == 0); // TODO: change after implementing multi-monitor support
        if (client.monitorId == monitorId and client.workspaceId == workspaceId) return;
        self.monitor.removeClient(client);
        self.monitor.addClient(client, workspaceId);
    }

    pub fn updateFocus(self: *Manager, forceUpdate: bool) void {
        const client = self.activeClient();
        if (!forceUpdate and self.focusedClient == client) return;

        if (self.focusedClient) |fc| fc.setFocusedBorder(false);

        self.focusedClient = client;
        if (client) |c| {
            // update border state and grab focus
            c.setFocusedBorder(true);
            _ = x11.XSetInputFocus(self.display, c.w, x11.RevertToPointerRoot, x11.CurrentTime);
            log.info("Focused client {}", .{c.w});
        } else {
            // reset focus
            _ = x11.XSetInputFocus(self.display, x11.PointerRoot, x11.RevertToPointerRoot, x11.CurrentTime);
            log.info("Cleared focus", .{});
        }
    }

    pub fn markLayoutDirty(m: *Manager) void {
        m.layoutDirty = true;
    }

    pub fn killClientWindow(self: *Self, client: *Client) void {
        self.eventHandler.killWindow(client.w) catch unreachable;
    }

    fn applyLayout(self: *Manager) void {
        log.trace("Apply layout", .{});

        // TODO: figure out a more elegant solution?
        var it = self.clients.clients.first;
        while (it) |node| : (it = node.next) node.data.move(.{ .x = -10000, .y = -10000 });

        self.activeMonitor().applyLayout(TileLayout);
        self.layoutDirty = false;

        // Skip EnterNotify events to avoid changing the focused window without delibarate mouse movement
        self.eventHandler.skipEnterWindowEvents();
    }
};
