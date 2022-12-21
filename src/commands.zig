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
        if (m.focused_client) |fc| {
            if (!fc.is_fullscreen) {
                const nextClient = m.activeWorkspace().nextClient(fc);
                m.focusClient(nextClient);
            }
        }
    }

    pub fn focusPrev(m: *Manager) void {
        if (m.focused_client) |fc| {
            if (!fc.is_fullscreen) {
                const prevClient = m.activeWorkspace().prevClient(fc);
                m.focusClient(prevClient);
            }
        }
    }

    pub fn swapMain(m: *Manager) void {
        const w = m.activeWorkspace();
        if (w.clients.items.len <= 1) return;

        if (m.focused_client) |client| {
            if (client.is_floating or client.is_fullscreen) {
                return;
            }
            const first_client = w.firstTileableClient().?;
            if (client != first_client) {
                w.swapClients(client, first_client);
                m.markLayoutDirty();
            } else {
                // focused client is already the first
                // swap it with the next one and activate the new first
                const next_client = w.nextTileableClient(client);
                if (client != next_client) {
                    w.swapClients(client, next_client);
                    m.focusClient(next_client);
                    m.markLayoutDirty();
                }
            }
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
            if (!client.is_fullscreen and !client.is_floating) {
                const w = m.activeWorkspace();
                const next_client = w.nextClient(client);
                if (client != next_client) {
                    w.swapClients(client, next_client);
                    m.markLayoutDirty();
                }
            }
        }
    }

    pub fn movePrev(m: *Manager) void {
        if (m.focused_client) |client| {
            if (!client.is_fullscreen and !client.is_floating) {
                const w = m.activeWorkspace();
                const prev_client = w.prevClient(client);
                if (client != prev_client) {
                    w.swapClients(client, prev_client);
                    m.markLayoutDirty();
                }
            }
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
