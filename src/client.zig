const std = @import("std");
const x11 = @import("x11.zig");
const vec = @import("vec.zig");
const Pos = vec.Pos;
const Size = vec.Size;

pub const Client = struct {
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

    pub fn init(win: x11.Window, t: u8, d: *x11.Display) Client {
        var c = Client{ .w = win, .tag = t, .d = d };
        c.setFocusedBorder(false);
        _ = x11.XSetWindowBorderWidth(c.d, c.w, border_width);
        c.updateSizeHints() catch unreachable;
        return c;
    }

    pub fn getGeometry(c: Client) !Geometry {
        var root: x11.Window = undefined;
        var x: i32 = 0;
        var y: i32 = 0;
        var w: u32 = 0;
        var h: u32 = 0;
        var bw: u32 = 0;
        var depth: u32 = 0;
        if (x11.XGetGeometry(c.d, c.w, &root, &x, &y, &w, &h, &bw, &depth) == 0)
            return error.Error;
        return Geometry{ .pos = Pos.init(x, y), .size = Size.init(w, h) };
    }

    pub fn updateSizeHints(c: *Client) !void {
        c.min_size = Size.init(1, 1);
        c.max_size = Size.init(100000, 100000);
        var hints: *x11.XSizeHints = x11.XAllocSizeHints();
        defer _ = x11.XFree(hints);
        var supplied: c_long = undefined;
        if (x11.XGetWMNormalHints(c.d, c.w, hints, &supplied) == 0) return error.XGetWMNormalHintsFailed;
        if ((hints.flags & x11.PMinSize != 0) and hints.min_width > 0 and hints.min_height > 0) {
            c.min_size = Size.init(hints.min_width, hints.min_height);
        }
        if (hints.flags & x11.PMaxSize != 0 and hints.max_width > 0 and hints.max_height > 0) {
            c.max_size = Size.init(hints.max_width, hints.max_height);
        }
    }

    pub fn setFocusedBorder(c: Client, focused: bool) void {
        _ = x11.XSetWindowBorder(c.d, c.w, if (focused) border_color_focused else border_color_normal);
    }

    pub fn move(c: Client, p: Pos) void {
        _ = x11.XMoveWindow(c.d, c.w, p.x, p.y);
    }

    pub fn resize(c: Client, sz: Size) void {
        const new_size = sz.clamp(c.min_size, c.max_size).sub(Size.init(2 * border_width, 2 * border_width));
        _ = x11.XResizeWindow(c.d, c.w, new_size.w, new_size.h);
    }

    pub fn moveResize(c: Client, pos: Pos, size: Size) void {
        const w = @intCast(u32, std.math.clamp(size.x, c.min_size.x, c.max_size.x) - 2 * border_width);
        const h = @intCast(u32, std.math.clamp(size.y, c.min_size.y, c.max_size.y) - 2 * border_width);
        _ = x11.XMoveResizeWindow(c.d, c.w, pos.x, pos.y, w, h);
    }
};

pub const ClientList = struct {
    const Self = @This();
    const List = std.TailQueue(Client);
    pub const Node = List.Node;

    list: List,

    pub fn init() ClientList {
        return Self{ .list = List{} };
    }

    pub fn deinit(self: *Self) void {
        var it = self.list.first;
        while (it) |n| : (it = n.next) destroyNode(n);
    }

    pub fn prependNewClient(self: *Self, window: x11.Window, tag: u8, display: *x11.Display) *Node {
        const n = createNode();
        n.data = Client.init(window, tag, display);
        self.list.prepend(n);
        return n;
    }

    pub fn deleteClient(self: *Self, node: *Node) void {
        self.list.remove(node);
        destroyNode(node);
    }

    pub fn isClientWindow(self: *const Self, w: x11.Window) bool {
        return self.findByWindow(w) != null;
    }

    pub fn findByWindow(self: *Self, w: x11.Window) ?*Node {
        var it = self.list.first;
        while (it) |n| : (it = n.next) if (n.data.w == w) return n;
        return null;
    }

    fn createNode() *Node {
        return std.heap.c_allocator.create(Node) catch unreachable;
    }

    fn destroyNode(node: *Node) void {
        std.heap.c_allocator.destroy(node);
    }
};