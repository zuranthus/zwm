const std = @import("std");
const x11 = @import("x11.zig");
const log = @import("./log.zig");
const c_import = @cImport({
    @cInclude("unistd.h");
});

const Error = error{
    Error,
    WindowIsNotClient,
    XGetWMNormalHintsFailed,
};

const Hotkeys = struct {
    const Hotkey = struct { mod: c_uint, key: c_ulong, fun: fn (*Manager) void };
    fn add(m: c_uint, k: c_ulong, f: fn (*Manager) void) Hotkey {
        return Hotkey{ .mod = m, .key = k, .fun = f };
    }

    fn killFocused(m: *Manager) void {
        if (m.focusedClient) |fc| m.killClient(fc) catch unreachable;
    }
    fn focusNext(m: *Manager) void {
        if (m.focusedClient) |fc| {
            const next = m.nextActiveClient(fc) orelse m.firstActiveClient();
            if (next) |c| m.focusClient(c);
        }
    }
    fn focusPrev(m: *Manager) void {
        if (m.focusedClient) |fc| {
            const prev = m.prevActiveClient(fc) orelse m.lastActiveClient();
            if (prev) |c| m.focusClient(c);
        }
    }
    fn swapMain(m: *Manager) void {
        if (m.focusedClient) |fc| {
            const mc = m.firstActiveClient() orelse unreachable;
            // if already main, swap with the next client
            const new_mc = if (fc != mc) fc else m.nextActiveClient(mc);
            if (new_mc) |nm| {
                m.clients.remove(nm);
                m.clients.prepend(nm);
                m.markLayoutDirty();
                m.focusClient(nm);
            }
        }
    }
    fn moveNext(m: *Manager) void {
        if (m.focusedClient) |fc| {
            const next = m.nextActiveClient(fc);
            m.clients.remove(fc);
            if (next) |c| m.clients.insertAfter(c, fc) else m.clients.prepend(fc);
            m.markLayoutDirty();
        }
    }
    fn movePrev(m: *Manager) void {
        if (m.focusedClient) |fc| {
            const prev = m.prevActiveClient(fc);
            m.clients.remove(fc);
            if (prev) |c| m.clients.insertBefore(c, fc) else m.clients.append(fc);
            m.markLayoutDirty();
        }
    }
    fn incMaster(m: *Manager) void {
        m.mainSize = std.math.min(m.mainSize + 10.0, 80.0);
        m.markLayoutDirty();
    }
    fn decMaster(m: *Manager) void {
        m.mainSize = std.math.max(m.mainSize - 10.0, 20.0);
        m.markLayoutDirty();
    }
    fn spawn(m: *Manager) void {
        const pid = std.os.fork() catch unreachable;
        if (pid == 0) {
            _ = c_import.close(x11.XConnectionNumber(m.d));
            _ = c_import.setsid();
            _ = c_import.execvp("alacritty", null);
            std.os.exit(0);
        }
    }

    // TODO replace with generic hotkeys
    fn selectTag1(m: *Manager) void {
        m.selectTag(1);
    }
    fn selectTag2(m: *Manager) void {
        m.selectTag(2);
    }
    fn selectTag3(m: *Manager) void {
        m.selectTag(3);
    }
    fn selectTag4(m: *Manager) void {
        m.selectTag(4);
    }
    fn selectTag5(m: *Manager) void {
        m.selectTag(5);
    }
    fn selectTag6(m: *Manager) void {
        m.selectTag(6);
    }
    fn selectTag7(m: *Manager) void {
        m.selectTag(7);
    }
    fn selectTag8(m: *Manager) void {
        m.selectTag(8);
    }
    fn selectTag9(m: *Manager) void {
        m.selectTag(9);
    }
    fn moveToTag(m: *Manager, tag: u8) void {
        if (m.activeTag == tag) return;
        if (m.focusedClient) |fc| {
            fc.data.tag = tag;
            m.focusClient(m.firstActiveClient());
            m.markLayoutDirty();
        }
    }
    fn moveToTag1(m: *Manager) void {
        moveToTag(m, 1);
    }
    fn moveToTag2(m: *Manager) void {
        moveToTag(m, 2);
    }
    fn moveToTag3(m: *Manager) void {
        moveToTag(m, 3);
    }
    fn moveToTag4(m: *Manager) void {
        moveToTag(m, 4);
    }
    fn moveToTag5(m: *Manager) void {
        moveToTag(m, 5);
    }
    fn moveToTag6(m: *Manager) void {
        moveToTag(m, 6);
    }
    fn moveToTag7(m: *Manager) void {
        moveToTag(m, 7);
    }
    fn moveToTag8(m: *Manager) void {
        moveToTag(m, 8);
    }
    fn moveToTag9(m: *Manager) void {
        moveToTag(m, 9);
    }

    const mod = x11.Mod1Mask;
    const list = [_]Hotkey{
        add(mod, x11.XK_C, killFocused),
        add(mod, x11.XK_H, decMaster),
        add(mod, x11.XK_L, incMaster),
        add(mod, x11.XK_J, focusNext),
        add(mod, x11.XK_K, focusPrev),
        add(mod, x11.XK_Return, swapMain),
        add(mod | x11.ShiftMask, x11.XK_Return, spawn),
        add(mod | x11.ShiftMask, x11.XK_J, moveNext),
        add(mod | x11.ShiftMask, x11.XK_K, movePrev),
        add(mod, x11.XK_1, selectTag1),
        add(mod, x11.XK_2, selectTag2),
        add(mod, x11.XK_3, selectTag3),
        add(mod, x11.XK_4, selectTag4),
        add(mod, x11.XK_5, selectTag5),
        add(mod, x11.XK_6, selectTag6),
        add(mod, x11.XK_7, selectTag7),
        add(mod, x11.XK_8, selectTag8),
        add(mod, x11.XK_9, selectTag9),
        add(mod | x11.ShiftMask, x11.XK_1, moveToTag1),
        add(mod | x11.ShiftMask, x11.XK_2, moveToTag2),
        add(mod | x11.ShiftMask, x11.XK_3, moveToTag3),
        add(mod | x11.ShiftMask, x11.XK_4, moveToTag4),
        add(mod | x11.ShiftMask, x11.XK_5, moveToTag5),
        add(mod | x11.ShiftMask, x11.XK_6, moveToTag6),
        add(mod | x11.ShiftMask, x11.XK_7, moveToTag7),
        add(mod | x11.ShiftMask, x11.XK_8, moveToTag8),
        add(mod | x11.ShiftMask, x11.XK_9, moveToTag9),
    };
};

const IntVec2 = struct {
    x: i32,
    y: i32,

    fn init(x: anytype, y: anytype) IntVec2 {
        return .{ .x = @intCast(i32, x), .y = @intCast(i32, y) };
    }
};
const Pos = IntVec2;
const Size = IntVec2;

const Drag = struct {
    start_pos: Pos,
    frame_pos: Pos,
    frame_size: Size,
};

const ClientList = std.TailQueue(Client);
const ClientNode = ClientList.Node;

const Client = struct {
    w: x11.Window,
    d: *x11.Display,
    tag: u8,
    min_size: Size = undefined,
    max_size: Size = undefined,

    const border_width = 3;
    const border_color_focused = 0xff8000;
    const border_color_normal = 0x808080;

    const Geometry = struct {
        pos: Pos,
        size: Size,
    };

    fn init(win: x11.Window, t: u8, d: *x11.Display) Client {
        var c = Client{ .w = win, .tag = t, .d = d };
        c.setFocusedBorder(false);
        _ = x11.XSetWindowBorderWidth(c.d, c.w, border_width);
        c.updateSizeHints() catch unreachable;
        return c;
    }

    fn getGeometry(c: Client) Error!Geometry {
        var root: x11.Window = undefined;
        var x: i32 = 0;
        var y: i32 = 0;
        var w: u32 = 0;
        var h: u32 = 0;
        var bw: u32 = 0;
        var depth: u32 = 0;
        if (x11.XGetGeometry(c.d, c.w, &root, &x, &y, &w, &h, &bw, &depth) == 0)
            return Error.Error;
        return Geometry{ .pos = Pos.init(x, y), .size = Size.init(w, h) };
    }

    fn updateSizeHints(c: *Client) !void {
        c.min_size = Size.init(1, 1);
        c.max_size = Size.init(100000, 100000);
        var hints: *x11.XSizeHints = x11.XAllocSizeHints();
        defer _ = x11.XFree(hints);
        var supplied: c_long = undefined;
        if (x11.XGetWMNormalHints(c.d, c.w, hints, &supplied) == 0) return Error.XGetWMNormalHintsFailed;
        if ((hints.flags & x11.PMinSize != 0) and hints.min_width > 0 and hints.min_height > 0) {
            c.min_size = Size.init(hints.min_width, hints.min_height);
        }
        if (hints.flags & x11.PMaxSize != 0 and hints.max_width > 0 and hints.max_height > 0) {
            c.max_size = Size.init(hints.max_width, hints.max_height);
        }
    }

    fn setFocusedBorder(c: Client, focused: bool) void {
        _ = x11.XSetWindowBorder(c.d, c.w, if (focused) border_color_focused else border_color_normal);
    }

    fn move(c: Client, p: Pos) void {
        _ = x11.XMoveWindow(c.d, c.w, p.x, p.y);
    }

    fn resize(c: Client, sz: Size) void {
        const new_size = sz.clamp(c.min_size, c.max_size).sub(Size.init(2 * border_width, 2 * border_width));
        _ = x11.XResizeWindow(c.d, c.w, new_size.w, new_size.h);
    }

    fn moveResize(c: Client, pos: Pos, size: Size) void {
        const w = @intCast(u32, std.math.clamp(size.x, c.min_size.x, c.max_size.x) - 2 * border_width);
        const h = @intCast(u32, std.math.clamp(size.y, c.min_size.y, c.max_size.y) - 2 * border_width);
        _ = x11.XMoveResizeWindow(c.d, c.w, pos.x, pos.y, w, h);
    }
};

const TileLayout = struct {
    pub fn apply(m: *const Manager, origin: Pos, size: Size, mainFactor: f32) void {
        const gap = 5;
        var pos = Pos.init(origin.x + gap, origin.y + gap);
        const len = @intCast(i32, m.countActiveClients());
        switch (len) {
            0 => return,
            1 => {
                const main_size = Size.init(size.x - 2 * gap, size.y - 2 * gap);
                m.firstActiveClient().?.data.moveResize(pos, main_size);
            },
            else => {
                const msize = Size.init(
                    @floatToInt(i32, @intToFloat(f32, size.x) * mainFactor) - gap,
                    size.y - 2 * gap,
                );
                var it = m.firstActiveClient();
                it.?.data.moveResize(pos, msize);
                pos.x += msize.x + gap;
                const ssize = Size.init(size.x - msize.x - 2 * gap, @divTrunc(size.y - gap, len - 1) - gap);
                it = m.nextActiveClient(it.?);
                while (it) |cn| : (it = m.nextActiveClient(cn)) {
                    cn.data.moveResize(pos, ssize);
                    pos.y += ssize.y + gap;
                }
            },
        }
    }
};

pub const Manager = struct {
    d: *x11.Display,
    root: x11.Window,
    drag: Drag = undefined,
    wm_delete: x11.Atom = undefined,
    wm_protocols: x11.Atom = undefined,
    layoutDirty: bool = false,
    size: Size = undefined,
    mainSize: f32 = 50.0,
    activeTag: u8 = 1,
    focusedClient: ?*ClientNode = null,
    focusedClientPerTag: [10]?*ClientNode = undefined,
    clients: ClientList = ClientList{},

    fn createClientNode(c: Client) *ClientNode {
        var n = std.heap.c_allocator.create(ClientNode) catch unreachable;
        n.data = c;
        return n;
    }
    fn destroyClientNode(node: *ClientNode) void {
        std.heap.c_allocator.destroy(node);
    }

    pub fn selectTag(self: *Manager, tag: u8) void {
        std.debug.assert(1 <= tag and tag <= 9);
        if (tag == self.activeTag) return;

        self.activeTag = tag;
        const client_to_focus = self.focusedClientPerTag[self.activeTag] orelse self.firstActiveClient();
        self.focusClient(client_to_focus);
        self.markLayoutDirty();
        log.info("Selected tag {} with {} clients", .{ tag, self.countActiveClients() });
    }

    fn focusClient(self: *Manager, client: ?*ClientNode) void {
        std.debug.assert(client == null or client.?.data.tag == self.activeTag);
        if (self.focusedClient) |fc| fc.data.setFocusedBorder(false);
        self.focusedClientPerTag[self.activeTag] = client;
        self.focusedClient = client;
        if (client) |c| {
            c.data.setFocusedBorder(true);
            _ = x11.XSetInputFocus(self.d, c.data.w, x11.RevertToPointerRoot, x11.CurrentTime);
            log.info("Focused client {}", .{c.data.w});
        } else {
            _ = x11.XSetInputFocus(self.d, x11.PointerRoot, x11.RevertToPointerRoot, x11.CurrentTime);
            log.info("Cleared focus", .{});
        }
    }

    pub fn init(_: ?[]u8) !Manager {
        if (isInstanceAlive) return error.WmInstanceAlreadyExists;
        const d = x11.XOpenDisplay(":1") orelse return error.CannotOpenDisplay;
        const r = x11.XDefaultRootWindow(d);
        isInstanceAlive = true;
        var m = Manager{
            .d = d,
            .root = r,
        };
        for (m.focusedClientPerTag) |*c| c.* = null;
        return m;
    }

    pub fn deinit(m: *Manager) void {
        std.debug.assert(isInstanceAlive);
        var it = m.clients.first;
        while (it) |cn| : (it = cn.next) destroyClientNode(cn);
        _ = x11.XUngrabKey(m.d, x11.AnyKey, x11.AnyModifier, m.root);
        _ = x11.XCloseDisplay(m.d);
        isInstanceAlive = false;
        log.info("destroyed wm", .{});
    }

    pub fn run(m: *Manager) !void {
        try m.initWm();
        try m.startEventLoop();
    }

    var isInstanceAlive = false;
    var isWmDetected = false;
    const modKey = x11.Mod1Mask;

    fn initWm(m: *Manager) !void {
        // check for another WM
        _ = x11.XSetErrorHandler(onWmDetected);
        _ = x11.XSelectInput(m.d, m.root, x11.SubstructureRedirectMask | x11.SubstructureNotifyMask);
        _ = x11.XSync(m.d, 0);
        if (Manager.isWmDetected) return error.AnotherWmDetected;
        _ = x11.XSetErrorHandler(onXError);

        _ = x11.XGrabServer(m.d);
        defer _ = x11.XUngrabServer(m.d);

        // Update metrics
        const screen = x11.XDefaultScreen(m.d);
        m.size = Size.init(
            x11.XDisplayWidth(m.d, screen),
            x11.XDisplayHeight(m.d, screen),
        );

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
        if (m.firstActiveClient()) |ac| m.focusClient(ac);

        // show cursor
        var wa = std.mem.zeroes(x11.XSetWindowAttributes);
        wa.cursor = x11.XCreateFontCursor(m.d, x11.XC_left_ptr);
        _ = x11.XChangeWindowAttributes(m.d, m.root, x11.CWCursor, &wa);

        // create atoms
        m.wm_delete = x11.XInternAtom(m.d, "WM_DELETE_WINDOW", 0);
        m.wm_protocols = x11.XInternAtom(m.d, "WM_PROTOCOLS", 0);

        // hotkeys
        _ = x11.XUngrabKey(m.d, x11.AnyKey, x11.AnyModifier, m.root);
        for (Hotkeys.list) |hk|
            _ = x11.XGrabKey(m.d, x11.XKeysymToKeycode(m.d, hk.key), hk.mod, m.root, 0, x11.GrabModeAsync, x11.GrabModeAsync);

        log.info("initialized wm", .{});
    }

    fn startEventLoop(m: *Manager) !void {
        while (true) {
            if (m.layoutDirty) m.applyLayout();

            var e = std.mem.zeroes(x11.XEvent);
            _ = x11.XNextEvent(m.d, &e);
            const ename = x11.eventTypeToString(@intCast(u8, e.type));
            try switch (e.type) {
                x11.CreateNotify => m.onCreateNotify(e.xcreatewindow),
                x11.DestroyNotify => m.onDestroyNotify(e.xdestroywindow),
                x11.ReparentNotify => m.onReparentNotify(e.xreparent),
                x11.MapNotify => m.onMapNotify(e.xmap),
                x11.UnmapNotify => m.onUnmapNotify(e.xunmap),
                x11.ConfigureNotify => {},
                x11.ConfigureRequest => m.onConfigureRequest(e.xconfigurerequest),
                x11.MapRequest => m.onMapRequest(e.xmaprequest),
                x11.ButtonPress => m.onButtonPress(e.xbutton),
                x11.ButtonRelease => m.onButtonRelease(e.xbutton),
                x11.MotionNotify => {
                    while (x11.XCheckTypedWindowEvent(m.d, e.xmotion.window, x11.MotionNotify, &e) != 0) {}
                    try m.onMotionNotify(e.xmotion);
                },
                x11.EnterNotify => m.onEnterNotify(e.xcrossing),
                x11.KeyPress => m.onKeyPress(e.xkey),
                x11.KeyRelease => m.onKeyRelease(e.xkey),
                else => log.trace("ignored event {s}", .{ename}),
            };
        }
    }

    fn onWmDetected(_: ?*x11.Display, err: [*c]x11.XErrorEvent) callconv(.C) c_int {
        const e: *x11.XErrorEvent = err;
        std.debug.assert(e.error_code == x11.BadAccess);
        Manager.isWmDetected = true;
        return 0;
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

    fn onCreateNotify(_: *Manager, ev: x11.XCreateWindowEvent) !void {
        log.trace("CreateNotify for {}", .{ev.window});
    }

    fn onDestroyNotify(_: *Manager, ev: x11.XDestroyWindowEvent) !void {
        log.trace("DestroyNotify for {}", .{ev.window});
    }

    fn onReparentNotify(_: *Manager, ev: x11.XReparentEvent) !void {
        log.trace("ReparentNotify for {} to {}", .{ ev.window, ev.parent });
    }

    fn onMapNotify(_: *Manager, ev: x11.XMapEvent) !void {
        log.trace("MapNotify for {}", .{ev.window});
    }

    fn onUnmapNotify(m: *Manager, ev: x11.XUnmapEvent) !void {
        const w = ev.window;
        log.trace("UnmapNotify for {}", .{w});

        m.removeClient(w);
    }

    fn onConfigureRequest(m: *Manager, ev: x11.XConfigureRequestEvent) !void {
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

    fn onMapRequest(m: *Manager, ev: x11.XMapRequestEvent) void {
        log.trace("MapRequest for {}", .{ev.window});
        const cn = m.addClient(ev.window);
        _ = x11.XMapWindow(m.d, ev.window);
        m.focusClient(cn);
    }

    fn addClient(m: *Manager, w: x11.Window) *ClientNode {
        std.debug.assert(!m.isClient(w));
        var wa = std.mem.zeroes(x11.XWindowAttributes);
        if (x11.XGetWindowAttributes(m.d, w, &wa) == 0) unreachable;
        _ = x11.XSelectInput(m.d, w, x11.EnterWindowMask | x11.SubstructureRedirectMask | x11.SubstructureNotifyMask);
        // move with mod + LB
        _ = x11.XGrabButton(m.d, x11.Button1, modKey, w, 0, x11.ButtonPressMask | x11.ButtonReleaseMask | x11.ButtonMotionMask, x11.GrabModeAsync, x11.GrabModeAsync, x11.None, x11.None);
        // resize with mod + RB
        _ = x11.XGrabButton(m.d, x11.Button3, modKey, w, 0, x11.ButtonPressMask | x11.ButtonReleaseMask | x11.ButtonMotionMask, x11.GrabModeAsync, x11.GrabModeAsync, x11.None, x11.None);
        const c = Client.init(w, m.activeTag, m.d);
        const cn = createClientNode(c);
        m.clients.prepend(cn);
        m.markLayoutDirty();
        log.info("Added client {}", .{w});
        log.trace("min_size ({}, {}), max_size ({}, {})", .{ c.min_size.x, c.min_size.y, c.max_size.x, c.max_size.y });
        return cn;
    }

    fn findClient(m: *Manager, w: x11.Window) *ClientNode {
        var it = m.clients.first;
        while (it) |cn| : (it = cn.next) if (cn.data.w == w) return cn;
        unreachable;
    }

    fn isClient(m: *Manager, w: x11.Window) bool {
        var it = m.clients.first;
        while (it) |cn| : (it = cn.next) if (cn.data.w == w) return true;
        return false;
    }

    fn removeClient(self: *Manager, w: x11.Window) void {
        const cn = self.findClient(w);
        self.clients.remove(cn);
        destroyClientNode(cn);
        self.markLayoutDirty();
        if (self.focusedClient == cn)
            self.focusClient(self.firstActiveClient());
        for (self.focusedClientPerTag) |*tf|
            if (tf.* == cn) {
                tf.* = null;
            };
        log.info("Removed client {}", .{w});
    }

    fn onButtonPress(m: *Manager, ev: x11.XButtonEvent) !void {
        log.trace("ButtonPress for {}", .{ev.window});
        const client = &m.findClient(ev.window).data;
        const g = try client.getGeometry();
        m.drag = Drag{
            .start_pos = Pos.init(ev.x_root, ev.y_root),
            .frame_pos = g.pos,
            .frame_size = g.size,
        };
        _ = x11.XRaiseWindow(m.d, client.w);
    }

    fn onButtonRelease(m: *Manager, ev: x11.XButtonEvent) !void {
        _ = m;
        _ = ev;
    }

    fn onMotionNotify(m: *Manager, ev: x11.XMotionEvent) !void {
        log.trace("MotionNotify for {}", .{ev.window});
        const c = &m.findClient(ev.window).data;
        const drag_pos = Pos.init(ev.x_root, ev.y_root);
        const delta = IntVec2.init(
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

    fn onEnterNotify(m: *Manager, ev: x11.XCrossingEvent) !void {
        log.trace("EnterNotify for {}", .{ev.window});
        if (ev.mode != x11.NotifyNormal or ev.detail == x11.NotifyInferior) return;
        const cn = m.findClient(ev.window);
        std.debug.assert(cn.data.tag == m.activeTag);
        m.focusClient(cn);
    }

    fn sendEvent(m: *Manager, w: x11.Window, protocol: x11.Atom) !void {
        var event = std.mem.zeroes(x11.XEvent);
        event.type = x11.ClientMessage;
        event.xclient.message_type = m.wm_protocols;
        event.xclient.window = w;
        event.xclient.format = 32;
        event.xclient.data.l[0] = @intCast(c_long, protocol);
        if (x11.XSendEvent(m.d, w, 0, x11.NoEventMask, &event) == 0) return error.Error;
    }

    fn killClient(m: *Manager, cn: *ClientNode) !void {
        const c = &cn.data;
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

    fn onKeyPress(m: *Manager, ev: x11.XKeyEvent) !void {
        for (Hotkeys.list) |hk|
            if (ev.keycode == x11.XKeysymToKeycode(m.d, hk.key) and ev.state ^ hk.mod == 0)
                hk.fun(m);
    }

    fn onKeyRelease(m: *Manager, ev: x11.XKeyEvent) !void {
        _ = m;
        _ = ev;
    }

    fn markLayoutDirty(m: *Manager) void {
        m.layoutDirty = true;
    }

    fn firstActiveClient(self: *const Manager) ?*ClientNode {
        var it = self.clients.first;
        while (it) |cn| : (it = cn.next)
            if (cn.data.tag == self.activeTag) return cn;
        return null;
    }
    fn lastActiveClient(self: *const Manager) ?*ClientNode {
        var it = self.clients.last;
        while (it) |cn| : (it = cn.prev)
            if (cn.data.tag == self.activeTag) return cn;
        return null;
    }

    fn nextActiveClient(self: *const Manager, cur: *const ClientNode) ?*ClientNode {
        var it = cur.next;
        while (it) |cn| : (it = cn.next)
            if (cn.data.tag == self.activeTag) return cn;
        return null;
    }

    fn prevActiveClient(self: *const Manager, cur: *const ClientNode) ?*ClientNode {
        var it = cur.prev;
        while (it) |cn| : (it = cn.prev)
            if (cn.data.tag == self.activeTag) return cn;
        return null;
    }

    fn countActiveClients(self: *const Manager) usize {
        var c: usize = 0;
        var it = self.firstActiveClient();
        while (it) |cn| : (it = self.nextActiveClient(cn)) c += 1;
        return c;
    }

    fn applyLayout(m: *Manager) void {
        log.trace("Apply layout", .{});
        // TODO
        var it = m.clients.first;
        while (it) |cn| : (it = cn.next)
            if (cn.data.tag != m.activeTag) cn.data.move(Pos.init(100000, 100000));
        TileLayout.apply(m, Pos.init(0, 0), m.size, m.mainSize / 100.0);
        m.layoutDirty = false;

        var ev: x11.XEvent = undefined;
        _ = x11.XSync(m.d, 0);
        // skip EnterNotify events
        while (x11.XCheckMaskEvent(m.d, x11.EnterWindowMask, &ev) != 0) {}
    }
};

pub fn main() !void {
    log.info("starting", .{});

    var m = try Manager.init(null);
    defer m.deinit();

    try m.run();

    log.info("exiting", .{});
}
