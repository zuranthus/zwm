const std = @import("std");

pub const testing = struct {
    pub fn expectEqual(actual: anytype, expected: anytype) !void {
        try std.testing.expectEqual(@as(@TypeOf(actual), expected), actual);
    }
};

pub const container = struct {
    /// TailQueue that owns its nodes. Nodes hold data of type T.
    /// Call deinit to free the memory and remove all nodes.
    // TODO pass allocator + tests
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
                var it = self.queue.first;
                while (it) |n| {
                    it = n.next;
                    destroyNode(n);
                }
                self.queue = Queue{};
            }

            pub fn prependNewNode(self: *Self, data: T) *Node {
                const n = createNode();
                n.data = data;
                self.queue.prepend(n);
                return n;
            }

            pub fn deleteNode(self: *Self, node: *Node) void {
                self.queue.remove(node);
                destroyNode(node);
            }

            fn createNode() *Node {
                return std.heap.c_allocator.create(Node) catch unreachable;
            }

            fn destroyNode(node: *Node) void {
                std.heap.c_allocator.destroy(node);
            }
        };
    }

    // TODO cleanup (make iter part of flist?)
    // TODO make more generic? one function for nextFiltered and prevFiltered?
    // TODO implement move before and after + tests
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
};

test "OwningTailQueue" {
    const T = i32;
    const List = container.OwningTailQueue(T);
    const expectEqual = testing.expectEqual;

    // empty deinit
    {
        var list = List.init();
        defer list.deinit();
    }

    // prependNewNode and deinit
    {
        var list = List.init();
        defer list.deinit();

        const node1 = list.prependNewNode(1);
        const node2 = list.prependNewNode(2);
        try expectEqual(node1.data, 1);
        try expectEqual(node2.data, 2);
        const first = list.queue.first;
        try expectEqual(first, node2);
        try expectEqual(first.?.next, node1);
        try expectEqual(first.?.prev, null);
        const last = list.queue.last;
        try expectEqual(last, node1);
        try expectEqual(last.?.prev, node2);
        try expectEqual(last.?.next, null);
    }

    // deleteNode and deinit
    {
        var list = List.init();
        defer list.deinit();

        const node1 = list.prependNewNode(1);
        const node2 = list.prependNewNode(2);
        list.deleteNode(node2);
        try expectEqual(list.queue.first, node1);
        list.deleteNode(node1);
        try expectEqual(list.queue.first, null);
        try expectEqual(list.queue.last, null);
    }
}

test "FilteredListIterator" {
    const T = i32;
    const FList = container.FilteredList(T);
    const Node = FList.Node;
    const Iter = FList.Iter;
    const gen = struct {
        fn filter(data: *const T) bool {
            return @rem(data.*, 2) == 0;
        }
    };
    const expectEqual = testing.expectEqual;
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
    const Iter = container.FilteredList(T).Iter;
    const expectEqual = testing.expectEqual;
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

    var list: List = undefined;
    const flist = container.FilteredList(T){ .list = &list, .filter = gen.filter };

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
