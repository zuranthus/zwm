// TODO: investigate adding tests?
const c_import = @cImport({
    @cInclude("unistd.h");
});
const std = @import("std");
const x11 = @import("x11.zig");
const Manager = @import("wm.zig").Manager;

pub fn selectTag(m: *Manager, tag: u8) void {
    m.activateWorkspace(tag);
    m.updateFocus(false);
    m.markLayoutDirty();
}

pub fn moveToTag(m: *Manager, tag: u8) void {
    if (m.activeWorkspace().id == tag) return;
    if (m.focused_client) |client| {
        m.moveClientToWorkspace(client, client.monitor_id.?, tag);
        m.updateFocus(false);
        m.markLayoutDirty();
    }
}

pub fn killFocused(m: *Manager) void {
    if (m.focused_client) |client| m.killClientWindow(client);
}

pub fn focusNext(m: *Manager) void {
    if (m.focused_client) |client| {
        const w = m.activeWorkspace();
        std.debug.assert(w.active_client == client);
        w.activateNextClient();
        m.updateFocus(false);
    }
}

pub fn focusPrev(m: *Manager) void {
    if (m.focused_client) |client| {
        const w = m.activeWorkspace();
        std.debug.assert(w.active_client == client);
        w.activatePrevClient();
        m.updateFocus(false);
    }
}

pub fn swapMain(m: *Manager) void {
    const w = m.activeWorkspace();
    if (w.clients.items.len <= 1) return;

    if (m.focused_client) |client| {
        std.debug.assert(w.active_client == client);
        if (client != w.clients.items[0]) {
            _ = w.swapWithFirst(client);
        } else {
            // focused client is already the first
            // swap it with the next one and activate the new first
            const new_active_client = w.swapWithNextClient(client);
            w.activateClient(new_active_client);
            m.updateFocus(false);
        }
        m.markLayoutDirty();
    }
}

pub fn incMaster(m: *Manager) void {
    m.monitor.mainSize = std.math.min(m.monitor.mainSize + 5.0, 80.0);
    m.markLayoutDirty();
}

pub fn decMaster(m: *Manager) void {
    m.monitor.mainSize = std.math.max(m.monitor.mainSize - 5.0, 20.0);
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
