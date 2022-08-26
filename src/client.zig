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

// TODO make into generic owning list?
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
        while (it) |n| : (it = n.next) _destroyNode(n);
    }

    pub fn prependNewClient(self: *Self, window: x11.Window, tag: u8, display: *x11.Display) *Node {
        const n = _createNode();
        n.data = Client.init(window, tag, display);
        self.list.prepend(n);
        return n;
    }

    pub fn deleteClient(self: *Self, node: *Node) void {
        self.list.remove(node);
        _destroyNode(node);
    }

    pub fn isClientWindow(self: *const Self, w: x11.Window) bool {
        return self.findByWindow(w) != null;
    }

    pub fn findByWindow(self: *Self, w: x11.Window) ?*Node {
        var it = self.list.first;
        while (it) |n| : (it = n.next) if (n.data.w == w) return n;
        return null;
    }

    fn _createNode() *Node {
        return std.heap.c_allocator.create(Node) catch unreachable;
    }

    fn _destroyNode(node: *Node) void {
        std.heap.c_allocator.destroy(node);
    }
};

/// TailQueue that owns its nodes.
/// Call deinit to free the memory.
// TODO pass allocator
pub fn OwningTailQueue(comptime T: type) type {
    return struct {
        const Self = @This();
        const Queue = std.TailQueue(T);
        pub const Node = Queue.Node;

        queue: Queue,

        pub fn init() Self {
            return Self{ .queue = Queue{} };
        }

        pub fn deinit(self: *Self) void {
            var it = self.list.first;
            while (it) |n| : (it = n.next) destroyNode(n);
        }

        pub fn prependNewNode(self: *Self, window: x11.Window, tag: u8, display: *x11.Display) *Node {
            const n = _createNode();
            n.data = Client.init(window, tag, display);
            self.list.prepend(n);
            return n;
        }

        pub fn deleteNode(self: *Self, node: *Node) void {
            self.list.remove(node);
            _destroyNode(node);
        }

        fn createNode() *Node {
            return std.heap.c_allocator.create(Node) catch unreachable;
        }

        fn destroyNode(node: *Node) void {
            std.heap.c_allocator.destroy(node);
        }
    };
}

// TODO cleanup
// TODO make more generic? one function for nextFiltered and prevFiltered?
// TODO implement move before and after
pub fn FilteredList(comptime T: type) type {
    const List = std.TailQueue(T);
    const FNode = List.Node;
    const FilterFn = fn (data: *const T) bool;

    const helper = struct {
        fn nextFiltered(node: ?*FNode, filter: FilterFn) ?*FNode {
            var it = node;
            while (it) |n| : (it = n.next) if (filter(&n.data)) break;
            return it;
        }

        fn prevFiltered(node: ?*FNode, filter: FilterFn) ?*FNode {
            var it = node;
            while (it) |n| : (it = n.prev) if (filter(&n.data)) break;
            return it;
        }
    };

    const FIter = struct {
        const Self = @This();
        pub const Node = FNode;

        node: ?*Node,
        filter: FilterFn,

        pub fn init(firstNode: ?*Node, filterFn: FilterFn) !Self {
            // check that the first node is passing the filter
            if (firstNode != null and !filterFn(&firstNode.?.data)) return error.InvalidNode;
            return Self{ .node = firstNode, .filter = filterFn };
        }

        pub fn data(self: *const Self) ?*T {
            return if (self.node != null) &self.node.?.data else null;
        }

        pub fn next(self: *Self) ?*Node {
            const result = self.node;
            if (self.node) |node| self.node = helper.nextFiltered(node.next, self.filter);
            return result;
        }

        pub fn prev(self: *Self) ?*Node {
            const result = self.node;
            if (self.node) |node| self.node = helper.prevFiltered(node.prev, self.filter);
            return result;
        }
    };

    const FList = struct {
        const Self = @This();
        pub const Node = FNode;
        pub const Iter = FIter;

        list: *List,
        filter: FilterFn,

        pub fn first(self: *const Self) Iter {
            var it = self.list.first;
            while (it) |n| : (it = n.next) if (self.filter(&n.data)) break;
            return Iter.init(it, self.filter) catch unreachable;
        }

        pub fn last(self: *const Self) Iter {
            var it = self.list.last;
            while (it) |n| : (it = n.prev) if (self.filter(&n.data)) break;
            return Iter.init(it, self.filter) catch unreachable;
        }

        pub fn count(self: *const Self) usize {
            var it = self.first();
            var c: usize = 0;
            while (it.next()) |_| c += 1;
            return c;
        }

        pub fn moveBefore(self: *Self, beforeNode: *Node, moveNode: *Node) void {
            std.debug.assert(self.isNodeInList(beforeNode));
            std.debug.assert(self.isNodeInList(moveNode));
            std.debug.assert(self.filter(beforeNode));
            std.debug.assert(self.filter(moveNode));
        }

        pub fn moveAfter(self: *Self, afterNode: *Node, moveNode: *Node) void {
            std.debug.assert(self.isNodeInList(afterNode));
            std.debug.assert(self.isNodeInList(moveNode));
            std.debug.assert(self.filter(afterNode));
            std.debug.assert(self.filter(moveNode));
        }

        // Returns true if node is part of the list. Used for debugging.
        fn isNodeInList(self: *const Self, node: *const Node) bool {
            var it = self.list.first;
            while (it) |n| : (it = n.next) if (n == node) return true;
            return false;
        }
    };

    return FList;
}

fn expectEqual(actual: anytype, expected: anytype) !void {
    try std.testing.expectEqual(@as(@TypeOf(actual), expected), actual);
}

test "FilteredListIterator" {
    const T = i32;
    const FList = FilteredList(T);
    const Node = FList.Node;
    const Iter = FList.Iter;
    const gen = struct {
        fn filter(data: *const T) bool {
            return @rem(data.*, 2) == 0;
        }
    };
    var node: Node = undefined;

    // Initialized from null
    {
        var it = try Iter.init(null, gen.filter);
        try expectEqual(it.node, null);
        try expectEqual(it.data(), null);
        try expectEqual(it.next(), null);
    }

    // Returns error if the input node is not filtered.
    {
        node.data = 1;
        try std.testing.expectError(error.InvalidNode, Iter.init(&node, gen.filter));
    }
}

test "FilteredList" {
    const T = i32;
    const List = std.TailQueue(T);
    const Node = List.Node;
    const Iter = FilteredList(T).Iter;
    const gen = struct {
        fn filter(data: *const T) bool {
            return @rem(data.*, 2) == 0;
        }

        fn expectIteratorToNode(iter: Iter, node: ?*Node) !void {
            var it = iter;
            try expectEqual(it.data(), if (node) |n| &n.data else null);
            try expectEqual(it.node, node);
            try expectEqual(it.next(), node);
        }
    };
    const expectIteratorToNode = gen.expectIteratorToNode;
    _ = expectIteratorToNode;

    var list: List = undefined;
    const flist = FilteredList(T){ .list = &list, .filter = gen.filter };

    // empty list
    {
        list = List{};

        try expectEqual(flist.count(), 0);

        try expectIteratorToNode(flist.first(), null);
        try expectIteratorToNode(flist.last(), null);
    }

    // single element (filtered out)
    {
        list = List{};
        var node = Node{ .data = 1 };
        list.append(&node);

        try expectEqual(flist.count(), 0);

        try expectIteratorToNode(flist.first(), null);
        try expectIteratorToNode(flist.last(), null);
    }

    // single element
    {
        list = List{};
        var node = Node{ .data = 2 };
        list.append(&node);

        try expectEqual(flist.count(), 1);

        try expectIteratorToNode(flist.first(), &node);
        try expectIteratorToNode(flist.last(), &node);
    }

    // multiple elements
    {
        list = List{};
        var nodes: [10]Node = undefined;
        for ([10]T{ 1, 4, 7, 8, 6, 1, 7, 9, 10, 13 }) |data, i| {
            nodes[i] = Node{ .data = data };
            list.append(&nodes[i]);
        }

        try expectEqual(flist.count(), 4);

        // check that iterators go through all items
        {
            var it = flist.last();
            var count: usize = 0;
            while (it.prev()) |_| count += 1;
            try expectEqual(count, 4);
        }

        // forward iter
        {
            var it = flist.first();
            try expectIteratorToNode(it, &nodes[1]);
            _ = it.next();
            try expectIteratorToNode(it, &nodes[3]);
            _ = it.next();
            try expectIteratorToNode(it, &nodes[4]);
            _ = it.next();
            try expectIteratorToNode(it, &nodes[8]);
            _ = it.next();
            try expectIteratorToNode(it, null);
        }
        // backward iter
        {
            var it = flist.last();
            try expectIteratorToNode(it, &nodes[8]);
            _ = it.prev();
            try expectIteratorToNode(it, &nodes[4]);
            _ = it.prev();
            try expectIteratorToNode(it, &nodes[3]);
            _ = it.prev();
            try expectIteratorToNode(it, &nodes[1]);
            _ = it.prev();
            try expectIteratorToNode(it, null);
        }
        // go forward and back
        {
            var it = flist.last();
            _ = it.prev();
            _ = it.next();
            try expectIteratorToNode(it, &nodes[8]);
        }
    }
}
