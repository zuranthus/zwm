const std = @import("std");

pub fn findIndex(slice: anytype, valueToFind: anytype) ?usize {
    checkSliceAndValueTypes(@TypeOf(slice), @TypeOf(valueToFind));

    for (slice) |e, i| if (e == valueToFind) return i;
    return null;
}

pub fn contains(slice: anytype, valueToFind: anytype) bool {
    checkSliceAndValueTypes(@TypeOf(slice), @TypeOf(valueToFind));

    return findIndex(slice, valueToFind) != null;
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