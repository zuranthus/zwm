const std = @import("std");
const print = std.debug.print;

const text_red = "\x1b[31m";
const text_gray = "\x1b[90m";
const text_reset = "\x1b[0m";

fn logColor(
    comptime cat: []const u8,
    comptime col: []const u8,
    comptime s: []const u8,
    args: anytype,
) void {
    const timestamp = @intCast(u64, std.time.timestamp());
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = timestamp };
    const day_seconds = epoch_seconds.getDaySeconds();
    print("{s}[{d:0<2}:{d:0<2}:{d:0<2}] {s} ", .{
        col,
        day_seconds.getHoursIntoDay(),
        day_seconds.getMinutesIntoHour(),
        day_seconds.getSecondsIntoMinute(),
        cat,
    });
    print(s, args);
    print("\n{s}", .{text_reset});
}

pub fn trace(comptime s: []const u8, args: anytype) void {
    logColor("[t]", text_gray, s, args);
}

pub fn info(comptime s: []const u8, args: anytype) void {
    logColor("[i]", "", s, args);
}

pub fn err(comptime s: []const u8, args: anytype) void {
    logColor("[e]", text_red, s, args);
}
