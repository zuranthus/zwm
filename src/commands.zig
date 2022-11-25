// TODO: investigate adding tests?
const c_import = @cImport({
    @cInclude("unistd.h");
});
const std = @import("std");
const x11 = @import("x11.zig");
const Manager = @import("wm.zig").Manager;

pub const api = struct {
    pub fn selectTag(m: *Manager, tag: u8) void {
        m.focusWorkspace(tag);
    }

    pub fn moveToTag(m: *Manager, tag: u8) void {
        if (m.activeWorkspace().id == tag) return;
        if (m.focused_client) |client| {
            m.moveClientToWorkspace(client, client.monitor_id.?, tag);
        }
    }

    pub fn killFocused(m: *Manager) void {
        if (m.focused_client) |client| m.killClientWindow(client);
    }

    pub fn focusNext(m: *Manager) void {
        if (m.focused_client != null) {
            m.focusNextClient();
        }
    }

    pub fn focusPrev(m: *Manager) void {
        if (m.focused_client != null) {
            m.focusPrevClient();
        }
    }

    pub fn swapMain(m: *Manager) void {
        const w = m.activeWorkspace();
        if (w.clients.items.len <= 1) return;

        if (m.focused_client) |client| {
            std.debug.assert(w.active_client == client);
            if (client != w.clients.items[0]) {
                _ = w.swapWithFirstClient(client);
            } else {
                // focused client is already the first
                // swap it with the next one and activate the new first
                const new_active_client = w.swapWithNextClient(client);
                m.focusClient(new_active_client);
            }
            m.markLayoutDirty();
        }
    }

    pub fn incMaster(m: *Manager) void {
        m.monitor.main_size = std.math.min(m.monitor.main_size + 5.0, 80.0);
        m.markLayoutDirty();
    }

    pub fn decMaster(m: *Manager) void {
        m.monitor.main_size = std.math.max(m.monitor.main_size - 5.0, 20.0);
        m.markLayoutDirty();
    }

    pub fn moveNext(m: *Manager) void {
        if (m.focused_client) |client| {
            const w = m.activeWorkspace();
            std.debug.assert(w.active_client == client);
            _ = w.swapWithNextClient(client);
            m.markLayoutDirty();
        }
    }

    pub fn movePrev(m: *Manager) void {
        if (m.focused_client) |client| {
            const w = m.activeWorkspace();
            std.debug.assert(w.active_client == client);
            _ = w.swapWithPrevClient(client);
            m.markLayoutDirty();
        }
    }

    pub fn spawn(m: *Manager, exec_name: [*c]const u8) void {
        const pid = std.os.fork() catch unreachable;
        if (pid == 0) {
            _ = c_import.close(x11.XConnectionNumber(m.display));
            _ = c_import.setsid();
            _ = c_import.execvp(exec_name, null);
            std.os.exit(0);
        }
    }

    pub fn quit(m: *Manager, code: u8) void {
        m.exit_code = code;
    }

    pub fn toggleBar(m: *Manager) void {
        m.toggleDockWindow();
    }
};

pub const MouseAction = enum { Move, Resize };

pub fn firstMatchingMouseAction(mouse_actions: anytype, button: u32, state: u32) ?MouseAction {
    inline for (mouse_actions) |a|
        if (button == a[2] and state ^ a[1] == 0)
            return a[0];
    return null;
}