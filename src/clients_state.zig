// The code in this file is not pretty, but it works and that is good enough for now...
const std = @import("std");
const x11 = @import("x11.zig");
const Manager = @import("wm.zig").Manager;

const format_version: u32 = 0x7A776D01;

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

    // active workspace
    const active_workspace_id = m.activeMonitor().active_workspace_id;
    try writer.writeIntLittle(u8, active_workspace_id);

    // main factor
    const main_factor: f32 = m.activeMonitor().mainSize;
    try writer.writeAll(std.mem.asBytes(&main_factor));

    // client state
    for (m.activeMonitor().workspaces) |*w| {
        var i:usize = w.clients.items.len;
        while (i > 0) {
            i -= 1;
            const c = w.clients.items[i];
            const state = State{
                .w = c.w,
                .m_id = c.monitor_id.?,
                .w_id = c.workspace_id.?,
            };
            try writer.writeStruct(state);
        }
    }
}

pub fn loadState(m: *Manager, state_file: []const u8) !void {
    const file = try std.fs.openFileAbsolute(state_file, .{});
    defer file.close();
    const reader = file.reader();

    // version
    const file_version = try reader.readIntLittle(@TypeOf(format_version));
    if (file_version != format_version) return error.IncompatibleFormatOrVersion;

    // active workspace
    const active_workspace_id = try reader.readIntLittle(u8);

    // main factor
    var main_factor: f32 = 50.0;
    _ = try reader.readAll(std.mem.asBytes(&main_factor));
    m.activeMonitor().mainSize = main_factor;

    // client state
    while (true) {
        const state = reader.readStruct(State) catch |e| {
            if (e == error.EndOfStream) break;
            return e;
        };
        var it = m.clients.list.first;
        while (it) |node| : (it = node.next) {
            const c = &node.data;
            if (node.data.w == state.w) {
                const mon = m.activeMonitor(); // TODO: multi-monitor
                mon.removeClient(c);
                mon.addClient(c, state.w_id);
            }
        }
    }

    m.focusWorkspace(active_workspace_id);
}
