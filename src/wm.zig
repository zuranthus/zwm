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
        if (m.focusedClient()) |fc| m.killClient(fc) catch unreachable;
    }
    fn focusNext(m: *Manager) void {
        const t = m.activeTag();
        if (t.activeClientIndex()) |i| {
            const next_i = (i + 1) % t.clients.items.len;
            const w = t.clients.items[next_i].w;
            t.setActiveWindow(w) catch unreachable;
            m.focusActiveWindow();
        }
    }
    fn focusPrev(m: *Manager) void {
        const t = m.activeTag();
        if (t.activeClientIndex()) |i| {
            const prev_i = if (i > 0) i - 1 else t.clients.items.len - 1;
            const w = t.clients.items[prev_i].w;
            t.setActiveWindow(w) catch unreachable;
            m.focusActiveWindow();
        }
    }
    fn swapMain(m: *Manager) void {
        const t = m.activeTag();
        if (t.clients.items.len <= 1) return;
        if (t.activeClientIndex()) |i| {
            // if already main, swap with the next client
            const c = t.clients.orderedRemove(if (i != 0) i else 1);
            t.clients.insert(0, c) catch unreachable;
            m.markLayoutDirty();
        }
    }
    fn moveNext(m: *Manager) void {
        const t = m.activeTag();
        if (t.clients.items.len <= 1) return;
        if (t.activeClientIndex()) |i| {
            const next_i = (i + 1) % t.clients.items.len;
            const c = t.clients.orderedRemove(i);
            t.clients.insert(next_i, c) catch unreachable;
            m.markLayoutDirty();
        }
    }
    fn movePrev(m: *Manager) void {
        const t = m.activeTag();
        if (t.clients.items.len <= 1) return;
        if (t.activeClientIndex()) |i| {
            const prev_i = if (i > 0) i - 1 else t.clients.items.len - 1;
            const c = t.clients.orderedRemove(i);
            t.clients.insert(prev_i, c) catch unreachable;
            m.markLayoutDirty();
        }
    }
    fn incMaster(m: *Manager) void {
        m.mainSize = std.math.min(m.mainSize + 10.0, 90.0);
        m.markLayoutDirty();
    }
    fn decMaster(m: *Manager) void {
        m.mainSize = std.math.max(m.mainSize - 10.0, 10.0);
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
    fn selectTag1(m: *Manager) void {
        m.selectTag(1);
    }
    fn selectTag2(m: *Manager) void {
        m.selectTag(2);
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
    };
};

const Pos = struct {
    x: i32,
    y: i32,

    fn init(x: anytype, y: anytype) Pos {
        return .{ .x = @intCast(i32, x), .y = @intCast(i32, y) };
    }

    fn minus(p: Pos, p2: Pos) Pos {
        return .{ .x = p.x - p2.x, .y = p.y - p2.y };
    }

    fn plus(p: Pos, p2: Pos) Pos {
        return .{ .x = p.x + p2.x, .y = p.y + p2.y };
    }
};

const Size = struct {
    w: u32,
    h: u32,

    fn init(w: anytype, h: anytype) Size {
        return .{ .w = @intCast(u32, w), .h = @intCast(u32, h) };
    }

    fn min() Size {
        return init(0, 0);
    }

    fn max() Size {
        const maxVal = std.math.maxInt(u32);
        return init(maxVal, maxVal);
    }

    fn sub(l: Size, r: Size) Size {
        return Size.init(l.w - r.w, l.h - r.h);
    }

    fn clamp(sz: Size, lower: Size, higher: Size) Size {
        return Size.init(
            std.math.clamp(sz.w, lower.w, higher.w),
            std.math.clamp(sz.h, lower.h, higher.h),
        );
    }
};

const Drag = struct {
    start_pos: Pos,
    frame_pos: Pos,
    frame_size: Size,
};

const Client = struct {
    w: x11.Window,
    d: *x11.Display,
    min_size: Size = Size.min(),
    max_size: Size = Size.max(),

    const border_width = 3;
    const border_color_focused = 0xff8000;
    const border_color_normal = 0x808080;

    const Geometry = struct {
        pos: Pos,
        size: Size,
    };

    fn init(win: x11.Window, d: *x11.Display) !Client {
        var c = Client{ .w = win, .d = d };
        try c.updateSizeHints();
        _ = x11.XSetWindowBorderWidth(c.d, c.w, border_width);
        c.setActive(false);
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
        var hints: *x11.XSizeHints = x11.XAllocSizeHints();
        defer _ = x11.XFree(hints);
        var supplied: c_long = undefined;
        if (x11.XGetWMNormalHints(c.d, c.w, hints, &supplied) == 0) return Error.XGetWMNormalHintsFailed;
        c.min_size = Size.init(1, 1);
        c.max_size = Size.max();
        if ((hints.flags & x11.PMinSize != 0) and hints.min_width > 0 and hints.min_height > 0) {
            c.min_size = Size.init(hints.min_width, hints.min_height);
        }
        if (hints.flags & x11.PMaxSize != 0 and hints.max_width > 0 and hints.max_height > 0) {
            c.max_size = Size.init(hints.max_width, hints.max_height);
        }
    }

    fn setActive(c: Client, focused: bool) void {
        _ = x11.XSetWindowBorder(c.d, c.w, if (focused) border_color_focused else border_color_normal);
    }

    fn move(c: Client, p: Pos) void {
        _ = x11.XMoveWindow(c.d, c.w, p.x, p.y);
    }

    fn resize(c: Client, sz: Size) void {
        const new_size = sz.clamp(c.min_size, c.max_size).sub(Size.init(2 * border_width, 2 * border_width));
        _ = x11.XResizeWindow(c.d, c.w, new_size.w, new_size.h);
    }

    fn moveResize(c: Client, p: Pos, sz: Size) void {
        const new_size = sz.clamp(c.min_size, c.max_size).sub(Size.init(2 * border_width, 2 * border_width));
        _ = x11.XMoveResizeWindow(c.d, c.w, p.x, p.y, new_size.w, new_size.h);
    }
};

const TileLayout = struct {
    pub fn apply(clients: []const Client, origin: Pos, size: Size, mainFactor: f32) void {
        const gap = 5;
        var pos = origin.plus(Pos.init(gap, gap));
        const len = clients.len;
        switch (len) {
            0 => return,
            1 => {
                clients[0].moveResize(pos, size.sub(Size.init(2 * gap, 2 * gap)));
            },
            else => {
                const msize = Size.init(
                    @floatToInt(u32, @intToFloat(f32, size.w) * mainFactor) - gap,
                    size.h - 2 * gap,
                );
                clients[0].moveResize(pos, msize);
                pos.x += @intCast(i32, msize.w) + gap;
                const ssize = Size.init(size.w - @intCast(u32, msize.w) - 2 * gap, (size.h - gap) / (len - 1) - gap);
                for (clients[1..]) |c| {
                    c.moveResize(pos, ssize);
                    pos.y += @intCast(i32, ssize.h) + gap;
                }
            },
        }
    }
};

const Clients = std.ArrayList(Client);

const Tag = struct {
    num: i8,
    clients: Clients = Clients.init(std.heap.c_allocator),
    activeWindow: ?x11.Window = null,

    pub fn deinit(self: *Tag) void {
        self.clients.deinit();
    }

    pub fn findClientIndex(self: *const Tag, w: x11.Window) Error!usize {
        return for (self.clients.items) |*c, i| {
            if (c.w == w) return i;
        } else return Error.WindowIsNotClient;
    }
    pub fn findClient(self: *const Tag, w: x11.Window) !*Client {
        const i = self.findClientIndex(w) catch return Error.WindowIsNotClient;
        return &self.clients.items[i];
    }
    pub fn activeClientIndex(self: *const Tag) ?usize {
        return if (self.activeWindow) |aw| self.findClientIndex(aw) catch unreachable else null;
    }
    pub fn activeClient(self: *const Tag) ?*Client {
        return if (self.activeClientIndex()) |i| &self.clients.items[i] else null;
    }
    pub fn clearActiveWindow(self: *Tag) void {
        if (self.activeClient()) |ac| ac.setActive(false);
        self.activeWindow = null;
    }
    pub fn setActiveWindow(self: *Tag, w: x11.Window) !void {
        self.clearActiveWindow();
        const c = try self.findClient(w);
        c.setActive(true);
        self.activeWindow = w;
    }
    pub fn removeClientWindow(self: *Tag, w: x11.Window) bool {
        for (self.clients.items) |*c, i|
            if (c.w == w) {
                if (self.activeWindow == w) self.clearActiveWindow();
                _ = self.clients.orderedRemove(i);
                if (self.clients.items.len > 0)
                    self.setActiveWindow(self.clients.items[0].w) catch unreachable;
                return true;
            };
        return false;
    }
};

pub const Manager = struct {
    tags: [10]Tag = undefined,
    d: *x11.Display,
    root: x11.Window,
    drag: Drag = undefined,
    wm_delete: x11.Atom = undefined,
    wm_protocols: x11.Atom = undefined,
    layoutDirty: bool = false,
    size: Size = undefined,
    mainSize: f32 = 50.0,
    _activeTag: u8 = 1,
    focusedWindow: ?x11.Window = null,

    fn activeTagClients(self: *Manager) *Clients {
        return &self.activeTag().clients;
    }
    fn activeTag(self: *Manager) *Tag {
        return &self.tags[self._activeTag];
    }
    fn focusedClient(self: *Manager) ?*Client {
        const t = self.activeTag();
        std.debug.assert(self.focusedWindow == null and t.activeWindow == null or self.focusedWindow.? == t.activeWindow.?);
        return t.activeClient();
    }

    pub fn selectTag(self: *Manager, tag: u8) void {
        if (tag < 1 or tag > 2) unreachable;
        if (tag == self._activeTag) return;

        self._activeTag = tag;
        self.focusActiveWindow();
        log.info("Selected tag {} with {} clients", .{ tag, self.activeTagClients().items.len });
    }

    fn focusActiveWindow(self: *Manager) void {
        if (self.activeTag().activeWindow) |aw| {
            self.focusedWindow = aw;
            _ = x11.XSetInputFocus(self.d, aw, x11.RevertToPointerRoot, x11.CurrentTime);
            log.info("Focused client {}", .{aw});
        } else {
            self.focusedWindow = null;
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
        for (m.tags) |*t, i| t.* = Tag{ .num = @intCast(i8, i) };
        return m;
    }

    pub fn deinit(m: *Manager) void {
        std.debug.assert(isInstanceAlive);
        _ = x11.XUngrabKey(m.d, x11.AnyKey, x11.AnyModifier, m.root);
        _ = x11.XCloseDisplay(m.d);

        for (m.tags) |*tag| tag.deinit();
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
        m.size.w = @intCast(u32, x11.XDisplayWidth(m.d, screen));
        m.size.h = @intCast(u32, x11.XDisplayHeight(m.d, screen));

        // manage existing visbile windows
        var root: x11.Window = undefined;
        var parent: x11.Window = undefined;
        var ws: [*c]x11.Window = null;
        var nws: c_uint = 0;
        _ = x11.XQueryTree(m.d, m.root, &root, &parent, &ws, &nws);
        defer _ = if (ws != null) x11.XFree(ws);
        std.debug.assert(root == m.root);
        if (nws > 0) {
            for (ws[0..nws]) |w| {
                var wa = std.mem.zeroes(x11.XWindowAttributes);
                if (x11.XGetWindowAttributes(m.d, w, &wa) == 0) {
                    log.err("XGetWindowAttributes failed for {}", .{w});
                    continue;
                }
                // Only add windows that are visible and don't set override_redirect
                if (wa.override_redirect == 0 and wa.map_state == x11.IsViewable) add_client: {
                    _ = m.addClient(w) catch |e| {
                        log.err("Add client {} failed with {}", .{ w, e });
                        break :add_client;
                    };
                    if (m.focusedWindow == null) {
                        try m.activeTag().setActiveWindow(w);
                        m.focusActiveWindow();
                    }
                } else {
                    log.info("Ignoring {}", .{w});
                }
            }
        }

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

        if (!m.isClient(w)) {
            log.trace("ignore UnmapNotify for non-client window {}", .{w});
        } else {
            try m.removeClient(w);
        }
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

    fn onMapRequest(m: *Manager, ev: x11.XMapRequestEvent) !void {
        log.trace("MapRequest for {}", .{ev.window});
        _ = try m.addClient(ev.window);
        _ = x11.XMapWindow(m.d, ev.window);
        try m.activeTag().setActiveWindow(ev.window);
        m.focusActiveWindow();
    }

    fn addClient(m: *Manager, w: x11.Window) !*Client {
        if (m.isClient(w)) return error.WindowAlreadyClient;

        var wa = std.mem.zeroes(x11.XWindowAttributes);
        if (x11.XGetWindowAttributes(m.d, w, &wa) == 0) return error.Error;

        // TODO move to Tag.addClient(c) ?
        const clients = m.activeTagClients();
        try clients.append(try Client.init(w, m.d));
        _ = x11.XSelectInput(m.d, w, x11.EnterWindowMask | x11.SubstructureRedirectMask | x11.SubstructureNotifyMask);

        // move with mod + LB
        _ = x11.XGrabButton(m.d, x11.Button1, modKey, w, 0, x11.ButtonPressMask | x11.ButtonReleaseMask | x11.ButtonMotionMask, x11.GrabModeAsync, x11.GrabModeAsync, x11.None, x11.None);
        // resize with mod + RB
        _ = x11.XGrabButton(m.d, x11.Button3, modKey, w, 0, x11.ButtonPressMask | x11.ButtonReleaseMask | x11.ButtonMotionMask, x11.GrabModeAsync, x11.GrabModeAsync, x11.None, x11.None);

        m.markLayoutDirty();

        const c = &clients.items[clients.items.len - 1];
        log.info("Added client {}", .{w});
        log.trace("min_size ({}, {}), max_size ({}, {})", .{ c.min_size.w, c.min_size.h, c.max_size.w, c.max_size.h });
        return c;
    }

    fn findClient(m: *Manager, w: x11.Window) Error!*Client {
        return for (m.tags) |*t| {
            if (t.findClient(w)) |c| return c else |_| {}
        } else Error.WindowIsNotClient;
    }

    fn isClient(m: *Manager, w: x11.Window) bool {
        _ = m.findClient(w) catch return false;
        return true;
    }

    fn removeClient(self: *Manager, w: x11.Window) !void {
        for (self.tags) |*t| {
            if (t.removeClientWindow(w)) break;
        } else return Error.WindowIsNotClient;
        self.focusActiveWindow();
        self.markLayoutDirty();
        log.info("Removed client {}", .{w});
    }

    fn onButtonPress(m: *Manager, ev: x11.XButtonEvent) !void {
        log.trace("ButtonPress for {}", .{ev.window});
        const client = try m.findClient(ev.window);
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
        const c = try m.findClient(ev.window);
        const drag_pos = Pos.init(ev.x_root, ev.y_root);
        const delta = drag_pos.minus(m.drag.start_pos);

        if (ev.state & x11.Button1Mask != 0) {
            const frame_pos = m.drag.frame_pos.plus(delta);
            log.info("Moving to ({}, {})", .{ frame_pos.x, frame_pos.y });
            _ = x11.XMoveWindow(m.d, c.w, frame_pos.x, frame_pos.y);
        } else if (ev.state & x11.Button3Mask != 0) {
            var w = @intCast(u32, std.math.max(
                @intCast(i32, c.min_size.w),
                @intCast(i32, m.drag.frame_size.w) + delta.x,
            ));
            var h = @intCast(u32, std.math.max(
                @intCast(i32, c.min_size.h),
                @intCast(i32, m.drag.frame_size.h) + delta.y,
            ));
            w = std.math.min(w, c.max_size.w);
            h = std.math.min(h, c.max_size.h);

            log.info("Resizing to ({}, {})", .{ w, h });
            _ = x11.XResizeWindow(m.d, ev.window, w, h);
        }
    }

    fn onEnterNotify(m: *Manager, ev: x11.XCrossingEvent) !void {
        log.trace("EnterNotify for {}", .{ev.window});
        if (ev.mode != x11.NotifyNormal or ev.detail == x11.NotifyInferior) return;
        try m.activeTag().setActiveWindow(ev.window);
        m.focusActiveWindow();
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

    fn killClient(m: *Manager, c: *Client) !void {
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

    fn applyLayout(m: *Manager) void {
        log.trace("Apply layout", .{});
        TileLayout.apply(m.activeTagClients().items, Pos.init(0, 0), m.size, m.mainSize / 100.0);
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
