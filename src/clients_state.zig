// The code in this file is not pretty, but it works and that is good enough for now...
const std = @import("std");
const x11 = @import("x11.zig");
const Manager = @import("wm.zig").Manager;

const format_version: u32 = 0x7A776D02; // "zwm\02"

const State = packed struct {
    w: x11.Window,
    m_id: u8,
    w_id: u8,
};

pub fn saveState(m: *Manager, state_file: []const u8) !void {
    const file = try std.fs.createFileAbsolute(state_file, .{});
    defer file.close();
    const writer = file.writer();

    // version
    try writer.writeIntLittle(@TypeOf(format_version), format_version);

    // main factor
    // TODO: move to root window property
    const main_factor: f32 = m.activeMonitor().main_size;
    try writer.writeAll(std.mem.asBytes(&main_factor));
}

pub fn loadState(m: *Manager, state_file: []const u8) !void {
    const file = try std.fs.openFileAbsolute(state_file, .{});
    defer file.close();
    const reader = file.reader();

    // version
    const file_version = try reader.readIntLittle(@TypeOf(format_version));
    if (file_version != format_version) return error.IncompatibleFormatOrVersion;

    // main factor
    var main_factor: f32 = 50.0;
    _ = try reader.readAll(std.mem.asBytes(&main_factor));
    m.activeMonitor().main_size = main_factor;
}
