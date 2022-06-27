const std = @import("std");
const print = std.debug.print;

const textRed = "\x1b[31m";
const textGray = "\x1b[90m";
const textReset = "\x1b[0m";

fn logColor(
    comptime cat: []const u8,
    comptime col: []const u8,
    comptime s: []const u8,
    args: anytype,
) void {
    print("{s}{s} ", .{ col, cat });
    print(s, args);
    print("{s}", .{textReset});
}

pub fn trace(comptime s: []const u8, args: anytype) void {
    logColor("[t]", textGray, s, args);
}

pub fn info(comptime s: []const u8, args: anytype) void {
    logColor("[i]", "", s, args);
}

pub fn err(comptime s: []const u8, args: anytype) void {
    logColor("[e]", textRed, s, args);
}
