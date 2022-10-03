// TODO: investigate adding tests?

const c_import = @cImport({
    @cInclude("unistd.h");
});
const std = @import("std");
const x11 = @import("x11.zig");
const wm = @import("wm.zig");
const Manager = wm.Manager;

const mod = x11.Mod1Mask;

pub const hotkeys = .{
    .{ mod | x11.ShiftMask, x11.XK_C, killFocused, .{} },
    .{ mod, x11.XK_J, focusNext, .{} },
    .{ mod, x11.XK_K, focusPrev, .{} },
    .{ mod, x11.XK_H, decMaster, .{} },
    .{ mod, x11.XK_L, incMaster, .{} },
    .{ mod, x11.XK_Return, swapMain, .{} },
    .{ mod | x11.ShiftMask, x11.XK_J, moveNext, .{} },
    .{ mod | x11.ShiftMask, x11.XK_K, movePrev, .{} },

    .{ mod, x11.XK_1, selectTag, .{1} },
    .{ mod, x11.XK_2, selectTag, .{2} },
    .{ mod, x11.XK_3, selectTag, .{3} },
    .{ mod, x11.XK_4, selectTag, .{4} },
    .{ mod, x11.XK_5, selectTag, .{5} },
    .{ mod, x11.XK_6, selectTag, .{6} },
    .{ mod, x11.XK_7, selectTag, .{7} },
    .{ mod, x11.XK_8, selectTag, .{8} },
    .{ mod, x11.XK_9, selectTag, .{9} },
    .{ mod | x11.ShiftMask, x11.XK_1, moveToTag, .{1} },
    .{ mod | x11.ShiftMask, x11.XK_2, moveToTag, .{2} },
    .{ mod | x11.ShiftMask, x11.XK_3, moveToTag, .{3} },
    .{ mod | x11.ShiftMask, x11.XK_4, moveToTag, .{4} },
    .{ mod | x11.ShiftMask, x11.XK_5, moveToTag, .{5} },
    .{ mod | x11.ShiftMask, x11.XK_6, moveToTag, .{6} },
    .{ mod | x11.ShiftMask, x11.XK_7, moveToTag, .{7} },
    .{ mod | x11.ShiftMask, x11.XK_8, moveToTag, .{8} },
    .{ mod | x11.ShiftMask, x11.XK_9, moveToTag, .{9} },
};

fn selectTag(m: *Manager, tag: u8) void {
    m.activateWorkspace(tag);
    m.updateFocus(false);
    m.markLayoutDirty();
}

fn moveToTag(m: *Manager, tag: u8) void {
    if (m.activeWorkspace().id == tag) return;
    if (m.focusedClient) |client| {
        m.moveClientToWorkspace(client, client.monitorId.?, tag);
        m.updateFocus(false);
        m.markLayoutDirty();
    }
}

fn killFocused(m: *Manager) void {
    if (m.focusedClient) |client| m.killClientWindow(client);
}

fn focusNext(m: *Manager) void {
    if (m.focusedClient) |client| {
        const w = m.activeWorkspace();
        std.debug.assert(w.activeClient == client);
        w.activateNextClient();
        m.updateFocus(false);
    }
}

fn focusPrev(m: *Manager) void {
    if (m.focusedClient) |client| {
        const w = m.activeWorkspace();
        std.debug.assert(w.activeClient == client);
        w.activatePrevClient();
        m.updateFocus(false);
    }
}

fn swapMain(m: *Manager) void {
    const w = m.activeWorkspace();
    if (w.clients.items.len <= 1) return;

    if (m.focusedClient) |client| {
        std.debug.assert(w.activeClient == client);
        if (client != w.clients.items[0]) {
            _ = w.swapWithFirst(client);
        } else {
            // focused client is already the first
            // swap it with the next one and activate the new first
            const newActiveClient = w.swapWithNextClient(client);
            w.activateClient(newActiveClient);
            m.updateFocus(false);
        }
        m.markLayoutDirty();
    }
}

fn incMaster(m: *Manager) void {
    m.monitor.mainSize = std.math.min(m.monitor.mainSize + 10.0, 80.0);
    m.markLayoutDirty();
}

fn decMaster(m: *Manager) void {
    m.monitor.mainSize = std.math.max(m.monitor.mainSize - 10.0, 20.0);
    m.markLayoutDirty();
}

fn moveNext(m: *Manager) void {
    if (m.focusedClient) |client| {
        const w = m.activeWorkspace();
        std.debug.assert(w.activeClient == client);
        _ = w.swapWithNextClient(client);
        m.markLayoutDirty();
    }
}

fn movePrev(m: *Manager) void {
    if (m.focusedClient) |client| {
        const w = m.activeWorkspace();
        std.debug.assert(w.activeClient == client);
        _ = w.swapWithPrevClient(client);
        m.markLayoutDirty();
    }
}
//     fn spawn(m: *Manager) void {
//         const pid = std.os.fork() catch unreachable;
//         if (pid == 0) {
//             _ = c_import.close(x11.XConnectionNumber(m.d));
//             _ = c_import.setsid();
//             _ = c_import.execvp("alacritty", null);
//             std.os.exit(0);
//         }
//     }
