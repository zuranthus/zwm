const std = @import("std");
const x11 = @import("x11.zig");
const log = @import("log.zig");
//const hotkeys = @import("hotkeys.zig");
const client_import = @import("client.zig");
const Client = client_import.Client;

const vec = @import("vec.zig");
const Pos = vec.Pos;
const Size = vec.Size;

const DragState = struct {
    start_pos: Pos,
    frame_pos: Pos,
    frame_size: Size,
};

const TileLayout = struct {
    pub fn apply(clients: []*const Client, origin: Pos, size: Size, mainFactor: f32) void {
        if (clients.len == 0) return;
        const gap = 5;
        var pos = Pos.init(origin.x + gap, origin.y + gap);

        if (clients.len == 1) {
            const main_size = Size.init(size.x - 2 * gap, size.y - 2 * gap);
            clients[0].moveResize(pos, main_size);
            return;
        }

        const msize = Size.init(
            @floatToInt(i32, @intToFloat(f32, size.x) * mainFactor) - gap,
            size.y - 2 * gap,
        );
        clients[0].moveResize(pos, msize);
        pos.x += msize.x + gap;
        const ssize = Size.init(
            size.x - msize.x - 2 * gap,
            @divTrunc(size.y - gap, @intCast(i32, clients.len) - 1) - gap,
        );
        for (clients[1..]) |c| {
            c.moveResize(pos, ssize);
            pos.y += ssize.y + gap;
        }
    }
};

pub const FocusContext = struct {
    d: *x11.Display,
    focusedClient: ?*Client = null,

    pub fn focusClient(self: *@This(), client: ?*Client) void {
        // update border state of previously focused client
        if (self.focusedClient) |fc| fc.setFocusedBorder(false);

        self.focusedClient = client;

        if (client) |c| {
            // update border state and grab focus
            c.setFocusedBorder(true);
            _ = x11.XSetInputFocus(self.d, c.w, x11.RevertToPointerRoot, x11.CurrentTime);
            log.info("Focused client {}", .{c.w});
        } else {
            // reset focus
            _ = x11.XSetInputFocus(self.d, x11.PointerRoot, x11.RevertToPointerRoot, x11.CurrentTime);
            log.info("Cleared focus", .{});
        }
    }

    pub fn onClientRemoved(self: *@This(), client: *Client) void {
        _ = self;
        _ = client;
        unreachable; //TODO implement
    }
};

fn findIndex(comptime T: type) fn (slice: []T, toFind: T) ?usize {
    const gen = struct {
        fn findIndexImpl(slice: []T, toFind: T) ?usize {
            for (slice) |e, i| if (e == toFind) return i;
            return null;
        }
    };
    return gen.findIndexImpl;
}

pub const Monitor = struct {
    const Self = @This();
    const Clients = std.ArrayList(*Client);

    size: Size,
    focus: *FocusContext,

    mainSize: f32 = 50.0,
    activeTag: u8 = 1,
    focusedClientPerTag: [10]usize = .{0} ** 10,
    clients: Clients = Clients.init(std.heap.c_allocator),

    pub fn deinit(self: *Monitor) void {
        self.clients.deinit();
    }

    pub fn selectTag(self: *Self, tag: u8) void {
        std.debug.assert(1 <= tag and tag <= 9);
        if (tag == self.activeTag) return;

        self.activeTag = tag;
        self.focus.focusClient(self.firstActiveClient());
        log.info("Selected tag {} with {} clients", .{ tag, self.countActiveClients() });
    }

    pub fn firstActiveClient(self: *const @This()) ?*Client {
        if (self.clients.items.len == 0) return null;
        return self.clients.items[self.focusedClientPerTag[self.activeTag]];
    }

    pub fn addClient(self: *@This(), client: *Client) void {
        self.clients.insert(0, client) catch unreachable;
    }

    pub fn removeClient(self: *@This(), client: *Client) void {
        const i = findIndex(*Client)(self.clients.items, client) orelse unreachable;
        _ = self.clients.orderedRemove(i);
    }

    pub fn applyLayout(self: *@This()) void {
        var activeClients: [128]*const Client = undefined;
        var activeClientsCount: usize = 0;
        for (self.clients.items) |c| {
            if (c.tag != self.activeTag) {
                c.move(Pos.init(100000, 100000));
            } else {
                activeClients[activeClientsCount] = c;
                activeClientsCount += 1;
            }
        }
        TileLayout.apply(activeClients[0..activeClientsCount], Pos.init(0, 0), self.size, self.mainSize / 100.0);
    }
};

const EventHandler = struct {
    const Self = @This();

    d: *x11.Display,

    pub fn processEvent(self: *Self) void {
        var e = std.mem.zeroes(x11.XEvent);
        _ = x11.XNextEvent(self.d, &e);
        const ename = x11.eventTypeToString(@intCast(u8, e.type));
        try switch (e.type) {
            x11.UnmapNotify => self.onUnmapNotify(e.xunmap),
            x11.ConfigureNotify => {},
            x11.ConfigureRequest => self.onConfigureRequest(e.xconfigurerequest),
            x11.MapRequest => self.onMapRequest(e.xmaprequest),
            x11.ButtonPress => self.onButtonPress(e.xbutton),
            x11.ButtonRelease => self.onButtonRelease(e.xbutton),
            x11.MotionNotify => {
                while (x11.XCheckTypedWindowEvent(self.d, e.xmotion.window, x11.MotionNotify, &e) != 0) {}
                try self.onMotionNotify(e.xmotion);
            },
            x11.EnterNotify => self.onEnterNotify(e.xcrossing),
            x11.KeyPress => self.onKeyPress(e.xkey),
            x11.KeyRelease => self.onKeyRelease(e.xkey),
            else => log.trace("ignored event {s}", .{ename}),
        };
    }

    fn onXError(d: ?*x11.Display, err: [*c]x11.XErrorEvent) callconv(.C) c_int {
        const e: *x11.XErrorEvent = err;
        var error_text: [1024:0]u8 = undefined;
        _ = x11.XGetErrorText(d, e.error_code, @ptrCast([*c]u8, &error_text), @sizeOf(@TypeOf(error_text)));
        log.err("ErrorEvent: request '{s}' xid {x}, error text '{s}'", .{
            x11.requestCodeToString(e.request_code),
            e.resourceid,
            error_text,
        });
        return 0;
    }

    fn onUnmapNotify(m: *Self, ev: x11.XUnmapEvent) !void {
        const w = ev.window;
        log.trace("UnmapNotify for {}", .{w});

        m.removeClient(w);
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
        _ = x11.XConfigureWindow(m.d, w, @intCast(c_uint, ev.value_mask), &changes);
        log.info("resize {} to ({}, {})", .{ w, changes.width, changes.height });
    }

    fn onMapRequest(m: *Self, ev: x11.XMapRequestEvent) void {
        log.trace("MapRequest for {}", .{ev.window});
        const cn = m.addClient(ev.window);
        _ = x11.XMapWindow(m.d, ev.window);
        m.focus.focusClient(cn);
    }

    fn onButtonPress(m: *Self, ev: x11.XButtonEvent) !void {
        log.trace("ButtonPress for {}", .{ev.window});
        const client = &(m.findByWindow(ev.window) orelse unreachable).data;
        const g = try client.getGeometry();
        m.drag = DragState{
            .start_pos = Pos.init(ev.x_root, ev.y_root),
            .frame_pos = g.pos,
            .frame_size = g.size,
        };
        _ = x11.XRaiseWindow(m.d, client.w);
    }

    fn onButtonRelease(m: *Self, ev: x11.XButtonEvent) !void {
        _ = m;
        _ = ev;
    }

    fn onMotionNotify(m: *Self, ev: x11.XMotionEvent) !void {
        log.trace("MotionNotify for {}", .{ev.window});
        const c = &(m.findByWindow(ev.window) orelse unreachable).data;
        const drag_pos = Pos.init(ev.x_root, ev.y_root);
        const delta = vec.IntVec2.init(
            drag_pos.x - m.drag.start_pos.x,
            drag_pos.y - m.drag.start_pos.y,
        );

        if (ev.state & x11.Button1Mask != 0) {
            const x = m.drag.frame_pos.x + delta.x;
            const y = m.drag.frame_pos.y + delta.y;
            log.info("Moving to ({}, {})", .{ x, y });
            _ = x11.XMoveWindow(m.d, c.w, x, y);
        } else if (ev.state & x11.Button3Mask != 0) {
            const w = @intCast(u32, std.math.clamp(
                m.drag.frame_size.x + delta.x,
                c.min_size.x,
                c.max_size.x,
            ));
            const h = @intCast(u32, std.math.clamp(
                m.drag.frame_size.y + delta.y,
                c.min_size.y,
                c.max_size.y,
            ));

            log.info("Resizing to ({}, {})", .{ w, h });
            _ = x11.XResizeWindow(m.d, ev.window, w, h);
        }
    }

    fn onEnterNotify(m: *Self, ev: x11.XCrossingEvent) !void {
        log.trace("EnterNotify for {}", .{ev.window});
        if (ev.mode != x11.NotifyNormal or ev.detail == x11.NotifyInferior) return;
        const cn = m.findByWindow(ev.window) orelse unreachable;
        m.focus.focusClient(&cn.data);
    }

    fn sendEvent(m: *Self, w: x11.Window, protocol: x11.Atom) !void {
        var event = std.mem.zeroes(x11.XEvent);
        event.type = x11.ClientMessage;
        event.xclient.message_type = m.wm_protocols;
        event.xclient.window = w;
        event.xclient.format = 32;
        event.xclient.data.l[0] = @intCast(c_long, protocol);
        if (x11.XSendEvent(m.d, w, 0, x11.NoEventMask, &event) == 0) return error.Error;
    }

    pub fn killClient(m: *Self, c: *Client) !void {
        var protocols: [*c]x11.Atom = null;
        var count: i32 = 0;
        _ = x11.XGetWMProtocols(m.d, c.w, &protocols, &count);
        defer _ = if (protocols != null) x11.XFree(protocols);

        const supports_delete = count > 0 and for (protocols[0..@intCast(usize, count)]) |p| {
            if (p == m.wm_delete) break true;
        } else false;
        if (supports_delete) {
            log.info("Sending wm_delete to {}", .{c.w});
            try sendEvent(m, c.w, m.wm_delete);
            return;
        }
        log.info("Killing {}", .{c.w});
        _ = x11.XKillClient(m.d, c.w);
    }

    fn onKeyPress(m: *Self, ev: x11.XKeyEvent) !void {
        _ = m;
        _ = ev;
        // TODO
        //for (hotkeys.Hotkeys.list) |hk|
        //    if (ev.keycode == x11.XKeysymToKeycode(m.d, hk.key) and ev.state ^ hk.mod == 0)
        //        hk.fun(m);
    }

    fn onKeyRelease(m: *Self, ev: x11.XKeyEvent) !void {
        _ = m;
        _ = ev;
    }
};

fn isAnotherWmDetected(d: *x11.Display, r: x11.Window) bool {
    const Checker = struct {
        var anotherWmDetected = false;

        fn onWmDetected(_: ?*x11.Display, err: [*c]x11.XErrorEvent) callconv(.C) c_int {
            const e: *x11.XErrorEvent = err;
            std.debug.assert(e.error_code == x11.BadAccess);
            anotherWmDetected = true;
            return 0;
        }
    };
    _ = x11.XSetErrorHandler(Checker.onWmDetected);
    _ = x11.XSelectInput(d, r, x11.SubstructureRedirectMask | x11.SubstructureNotifyMask);
    _ = x11.XSync(d, 0);
    return Checker.anotherWmDetected;
}

pub const Manager = struct {
    const Self = @This();
    const AllClients = std.SinglyLinkedList(Client);

    d: *x11.Display,
    root: x11.Window,
    drag: DragState = undefined,
    wm_delete: x11.Atom = undefined,
    wm_protocols: x11.Atom = undefined,
    layoutDirty: bool = false,
    monitor: Monitor = undefined,
    allClients: AllClients = .{},
    focus: FocusContext = undefined,
    eventHandler: EventHandler = undefined,

    pub fn init(_: ?[]u8) !Manager {
        if (isInstanceAlive) return error.WmInstanceAlreadyExists;
        const d = x11.XOpenDisplay(":1") orelse return error.CannotOpenDisplay;
        const r = x11.XDefaultRootWindow(d);
        isInstanceAlive = true;
        var m = Manager{
            .d = d,
            .root = r,
        };
        return m;
    }

    pub fn deinit(self: *Manager) void {
        std.debug.assert(isInstanceAlive);
        self.monitor.deinit();
        _ = x11.XUngrabKey(self.d, x11.AnyKey, x11.AnyModifier, self.root);
        _ = x11.XCloseDisplay(self.d);
        isInstanceAlive = false;
        log.info("destroyed wm", .{});
    }

    pub fn run(m: *Manager) !void {
        try m.initWm();
        try m.startEventLoop();
    }

    var isInstanceAlive = false;
    const modKey = x11.Mod1Mask;

    fn initWm(m: *Manager) !void {
        if (isAnotherWmDetected(m.d, m.root)) return error.AnotherWmDetected;
        // TODO
        //_ = x11.XSetErrorHandler(onXError);

        _ = x11.XGrabServer(m.d);
        defer _ = x11.XUngrabServer(m.d);

        // Initialize
        m.focus = .{ .d = m.d };
        m.eventHandler = .{ .d = m.d };
        const screen = x11.XDefaultScreen(m.d);
        m.monitor = Monitor{
            .size = Size.init(
                x11.XDisplayWidth(m.d, screen),
                x11.XDisplayHeight(m.d, screen),
            ),
            .focus = &m.focus,
        };

        // manage existing visbile windows
        var root: x11.Window = undefined;
        var parent: x11.Window = undefined;
        var ws: [*c]x11.Window = null;
        var nws: c_uint = 0;
        _ = x11.XQueryTree(m.d, m.root, &root, &parent, &ws, &nws);
        defer _ = if (ws != null) x11.XFree(ws);
        std.debug.assert(root == m.root);
        if (nws > 0) for (ws[0..nws]) |w| {
            var wa = std.mem.zeroes(x11.XWindowAttributes);
            if (x11.XGetWindowAttributes(m.d, w, &wa) == 0) {
                log.err("XGetWindowAttributes failed for {}", .{w});
                continue;
            }
            // Only add windows that are visible and don't set override_redirect
            if (wa.override_redirect == 0 and wa.map_state == x11.IsViewable)
                _ = m.addClient(w)
            else
                log.info("Ignoring {}", .{w});
        };
        if (m.monitor.firstActiveClient()) |ac| m.focus.focusClient(ac);

        // show cursor
        var wa = std.mem.zeroes(x11.XSetWindowAttributes);
        wa.cursor = x11.XCreateFontCursor(m.d, x11.XC_left_ptr);
        _ = x11.XChangeWindowAttributes(m.d, m.root, x11.CWCursor, &wa);

        // create atoms
        m.wm_delete = x11.XInternAtom(m.d, "WM_DELETE_WINDOW", 0);
        m.wm_protocols = x11.XInternAtom(m.d, "WM_PROTOCOLS", 0);

        // TODO
        // hotkeys
        //_ = x11.XUngrabKey(m.d, x11.AnyKey, x11.AnyModifier, m.root);
        //for (hotkeys.Hotkeys.list) |hk|
        //    _ = x11.XGrabKey(m.d, x11.XKeysymToKeycode(m.d, hk.key), hk.mod, m.root, 0, x11.GrabModeAsync, x11.GrabModeAsync);

        log.info("initialized wm", .{});
    }

    fn startEventLoop(m: *Manager) !void {
        while (true) {
            if (m.layoutDirty) m.applyLayout();
            m.eventHandler.processEvent();
        }
    }


    fn addClient(self: *Self, w: x11.Window) *Client {
        std.debug.assert(self.findByWindow(w) == null);
        var wa = std.mem.zeroes(x11.XWindowAttributes);
        if (x11.XGetWindowAttributes(self.d, w, &wa) == 0) unreachable;
        _ = x11.XSelectInput(self.d, w, x11.EnterWindowMask | x11.SubstructureRedirectMask | x11.SubstructureNotifyMask);
        // move with mod + LB
        _ = x11.XGrabButton(
            self.d,
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
        _ = x11.XGrabButton(self.d, x11.Button3, modKey, w, 0, x11.ButtonPressMask | x11.ButtonReleaseMask | x11.ButtonMotionMask, x11.GrabModeAsync, x11.GrabModeAsync, x11.None, x11.None);
        const newNode = std.heap.c_allocator.create(AllClients.Node) catch unreachable;
        newNode.data = Client.init(w, self.monitor.activeTag, self.d);
        self.allClients.prepend(newNode);
        const c = &newNode.data;
        self.monitor.addClient(c);
        self.markLayoutDirty();
        log.info("Added client {}", .{w});
        log.trace("min_size ({}, {}), max_size ({}, {})", .{ c.min_size.x, c.min_size.y, c.max_size.x, c.max_size.y });
        return c;
    }

    fn findByWindow(self: *Manager, w: x11.Window) ?*AllClients.Node {
        _ = self;
        _ = w;
        unreachable;
    }

    fn removeClient(self: *Manager, w: x11.Window) void {
        const node = self.findByWindow(w) orelse unreachable;
        const client = &node.data;
        self.allClients.remove(node);
        self.monitor.removeClient(client);
        self.focus.onClientRemoved(client);
        std.heap.c_allocator.destroy(node);
        self.markLayoutDirty();
        log.info("Removed client {}", .{w});
    }


    pub fn markLayoutDirty(m: *Manager) void {
        m.layoutDirty = true;
    }

    fn applyLayout(m: *Manager) void {
        log.trace("Apply layout", .{});
        m.monitor.applyLayout();
        m.layoutDirty = false;

        // skip EnterNotify events
        var ev: x11.XEvent = undefined;
        _ = x11.XSync(m.d, 0);
        while (x11.XCheckMaskEvent(m.d, x11.EnterWindowMask, &ev) != 0) {}
    }
};
