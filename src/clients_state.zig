const std = @import("std");
const x11 = @import("x11.zig");
const Client = @import("client.zig").Client;
const Manager = @import("wm.zig").Manager;

const State = packed struct {
    index: usize,
    w: x11.Window,
    m_id: u8,
    w_id: u8,
};

pub fn saveState(m: *Manager, state_file: []const u8) !void {
    const file = try std.fs.createFileAbsolute(state_file, .{});
    defer file.close();
    const writer = file.writer();

    var it = m.clients.list.first;
    while (it) |node| : (it = node.next) {
        const c = &node.data;
        const state = State{
            .index = 0, // TODO: implement
            .w = c.w,
            .m_id = c.monitor_id.?,
            .w_id = c.workspace_id.?,
        };
        try writer.writeStruct(state);
    }
}

pub fn loadState(m: *Manager, state_file: []const u8) !void {
    const file = try std.fs.openFileAbsolute(state_file, .{});
    defer file.close();
    const reader = file.reader();

    while (true) {
        const state = reader.readStruct(State) catch |e| {
            if (e == error.EndOfStream) break;
            return e;
        };
        var it = m.clients.list.first;
        while (it) |node| : (it = node.next) {
            const c = &node.data;
            if (node.data.w == state.w) {
                m.moveClientToWorkspace(c, state.m_id, state.w_id);
            }
        }
    }
}
