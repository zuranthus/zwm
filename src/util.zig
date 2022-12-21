const std = @import("std");

// TODO: get rid fo these
pub const IntVec2 = struct {
    x: i32,
    y: i32,

    pub fn init(x: anytype, y: anytype) IntVec2 {
        return IntVec2{ .x = @intCast(i32, x), .y = @intCast(i32, y) };
    }

    pub fn addVec(self: IntVec2, other: IntVec2) IntVec2 {
        return self.add(other.x, other.y);
    }

    pub fn add(self: IntVec2, x: anytype, y: anytype) IntVec2 {
        return IntVec2{ .x = self.x + @intCast(i32, x), .y = self.y + @intCast(i32, y) };
    }

    pub fn sub(self: IntVec2, x: anytype, y: anytype) IntVec2 {
        return IntVec2{ .x = self.x - @intCast(i32, x), .y = self.y - @intCast(i32, y) };
    }

    pub fn eq(self: IntVec2, other: IntVec2) bool {
        return self.x == other.x and self.y == other.y;
    }
};
pub const Pos = IntVec2;
pub const Size = IntVec2;

pub fn clipWindowPosSize(screen_origin: Pos, screen_size: Size, pos: *Pos, size: *Size) void {
    // clip window size - do nothing (for now?)
    // clip window pos
    const mx = screen_origin.x + screen_size.x;
    const my = screen_origin.y + screen_size.y;
    var pos_out = pos;
    if (pos_out.x >= mx) pos_out.x = mx - size.x;
    if (pos_out.y >= my) pos_out.y = my - size.y;
    if (pos_out.x + size.x <= screen_origin.x) pos_out.x = screen_origin.x;
    if (pos_out.y + size.y <= screen_origin.y) pos_out.y = screen_origin.y;
}

pub fn findIndex(slice: anytype, value_to_find: anytype) ?usize {
    checkSliceAndValueTypes(@TypeOf(slice), @TypeOf(value_to_find));

    for (slice) |e, i| if (e == value_to_find) return i;
    return null;
}

pub fn contains(slice: anytype, value_to_find: anytype) bool {
    checkSliceAndValueTypes(@TypeOf(slice), @TypeOf(value_to_find));

    return findIndex(slice, value_to_find) != null;
}

pub fn swap(slice: anytype, i: usize, j: usize) void {
    checkSliceType(@TypeOf(slice));

    const v = slice[i];
    slice[i] = slice[j];
    slice[j] = v;
}

pub fn nextIndex(slice: anytype, i: usize) usize {
    checkSliceType(@TypeOf(slice));

    return if (i + 1 >= slice.len) 0 else i + 1;
}

pub fn prevIndex(slice: anytype, i: usize) usize {
    checkSliceType(@TypeOf(slice));

    return if (i == 0) slice.len - 1 else i - 1;
}

pub fn OwningList(comptime Type: type) type {
    return struct {
        const Self = @This();
        const List = std.SinglyLinkedList(Type);
        pub const Node = List.Node;

        list: List = List{},

        pub fn init() Self {
            return .{};
        }

        pub fn deinit(self: *Self) void {
            while (self.list.first) |node| self.destroyNode(node);
        }

        pub fn createNode(self: *Self) *Node {
            const newNode = std.heap.c_allocator.create(Node) catch unreachable;
            self.list.prepend(newNode);
            return newNode;
        }

        pub fn moveNodeToFront(self: *Self, node: *Node) void {
            self.list.remove(node);
            self.list.prepend(node);
        }

        pub fn destroyNode(self: *Self, node: *Node) void {
            self.list.remove(node);
            std.heap.c_allocator.destroy(node);
        }

        pub fn findNodeByData(self: *Self, data: anytype) ?*Node {
            std.debug.assert(@TypeOf(data) == Type);

            var it = self.list.first;
            while (it) |node| : (it = node.next)
                if (node.data == data) return node;
            return null;
        }
    };
}

pub const Struts = struct {
    left: i32 = 0,
    right: i32 = 0,
    top: i32 = 0,
    bottom: i32 = 0,
};

// Helper functions
const assert = std.debug.assert;

fn checkSliceType(comptime Slice: type) void {
    const sliceInfo = @typeInfo(Slice);
    assert(sliceInfo == .Pointer);
    assert(sliceInfo.Pointer.size == .Slice);
}

fn checkSliceAndValueTypes(comptime Slice: type, comptime Value: type) void {
    checkSliceType(Slice);
    std.debug.assert(@typeInfo(Slice).Pointer.child == Value);
}
