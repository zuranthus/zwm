const c_import = @cImport({
    @cInclude("unistd.h");
});
const std = @import("std");
const x11 = @import("x11.zig");
const wm = @import("wm.zig");
const Manager = wm.Manager;

pub const Hotkeys = struct {
    const Hotkey = struct { mod: c_uint, key: c_ulong, fun: fn (*Manager) void };
    fn add(m: c_uint, k: c_ulong, f: fn (*Manager) void) Hotkey {
        return Hotkey{ .mod = m, .key = k, .fun = f };
    }

    fn killFocused(m: *Manager) void {
        if (m.focusedClient) |fc| m.killClient(fc) catch unreachable;
    }
    fn focusNext(m: *Manager) void {
        if (m.focusedClient) |fc| {
            const next = m.nextActiveClient(fc) orelse m.firstActiveClient();
            if (next) |c| m.focusClient(c);
        }
    }
    fn focusPrev(m: *Manager) void {
        if (m.focusedClient) |fc| {
            const prev = m.prevActiveClient(fc) orelse m.lastActiveClient();
            if (prev) |c| m.focusClient(c);
        }
    }
    fn swapMain(m: *Manager) void {
        if (m.focusedClient) |fc| {
            const mc = m.firstActiveClient() orelse unreachable;
            // if already main, swap with the next client
            const new_mc = if (fc != mc) fc else m.nextActiveClient(mc);
            if (new_mc) |nm| {
                m.clients.remove(nm);
                m.clients.prepend(nm);
                m.markLayoutDirty();
                m.focusClient(nm);
            }
        }
    }
    fn moveNext(m: *Manager) void {
        if (m.focusedClient) |fc| {
            const next = m.nextActiveClient(fc);
            m.clients.remove(fc);
            if (next) |c| m.clients.insertAfter(c, fc) else m.clients.prepend(fc);
            m.markLayoutDirty();
        }
    }
    fn movePrev(m: *Manager) void {
        if (m.focusedClient) |fc| {
            const prev = m.prevActiveClient(fc);
            m.clients.remove(fc);
            if (prev) |c| m.clients.insertBefore(c, fc) else m.clients.append(fc);
            m.markLayoutDirty();
        }
    }
    fn incMaster(m: *Manager) void {
        m.mainSize = std.math.min(m.mainSize + 10.0, 80.0);
        m.markLayoutDirty();
    }
    fn decMaster(m: *Manager) void {
        m.mainSize = std.math.max(m.mainSize - 10.0, 20.0);
        m.markLayoutDirty();
    }
    fn spawn(m: *Manager) void {
        const pid = std.os.fork() catch unreachable;
        if (pid == 0) {
            _ = c_import.close(x11.XConnectionNumber(m.d));
            _ = c_import.setsid();
            _ = c_import.execvp("alacritty", null);
            std.os.exit(0);
        }
    }

    // TODO replace with generic hotkeys
    fn selectTag1(m: *Manager) void {
        m.selectTag(1);
    }
    fn selectTag2(m: *Manager) void {
        m.selectTag(2);
    }
    fn selectTag3(m: *Manager) void {
        m.selectTag(3);
    }
    fn selectTag4(m: *Manager) void {
        m.selectTag(4);
    }
    fn selectTag5(m: *Manager) void {
        m.selectTag(5);
    }
    fn selectTag6(m: *Manager) void {
        m.selectTag(6);
    }
    fn selectTag7(m: *Manager) void {
        m.selectTag(7);
    }
    fn selectTag8(m: *Manager) void {
        m.selectTag(8);
    }
    fn selectTag9(m: *Manager) void {
        m.selectTag(9);
    }
    fn moveToTag(m: *Manager, tag: u8) void {
        if (m.activeTag == tag) return;
        if (m.focusedClient) |fc| {
            fc.data.tag = tag;
            m.focusClient(m.firstActiveClient());
            m.markLayoutDirty();
        }
    }
    fn moveToTag1(m: *Manager) void {
        moveToTag(m, 1);
    }
    fn moveToTag2(m: *Manager) void {
        moveToTag(m, 2);
    }
    fn moveToTag3(m: *Manager) void {
        moveToTag(m, 3);
    }
    fn moveToTag4(m: *Manager) void {
        moveToTag(m, 4);
    }
    fn moveToTag5(m: *Manager) void {
        moveToTag(m, 5);
    }
    fn moveToTag6(m: *Manager) void {
        moveToTag(m, 6);
    }
    fn moveToTag7(m: *Manager) void {
        moveToTag(m, 7);
    }
    fn moveToTag8(m: *Manager) void {
        moveToTag(m, 8);
    }
    fn moveToTag9(m: *Manager) void {
        moveToTag(m, 9);
    }

    const mod = x11.Mod1Mask;
    pub const list = [_]Hotkey{
        add(mod, x11.XK_C, killFocused),
        add(mod, x11.XK_H, decMaster),
        add(mod, x11.XK_L, incMaster),
        add(mod, x11.XK_J, focusNext),
        add(mod, x11.XK_K, focusPrev),
        add(mod, x11.XK_Return, swapMain),
        add(mod | x11.ShiftMask, x11.XK_Return, spawn),
        add(mod | x11.ShiftMask, x11.XK_J, moveNext),
        add(mod | x11.ShiftMask, x11.XK_K, movePrev),
        add(mod, x11.XK_1, selectTag1),
        add(mod, x11.XK_2, selectTag2),
        add(mod, x11.XK_3, selectTag3),
        add(mod, x11.XK_4, selectTag4),
        add(mod, x11.XK_5, selectTag5),
        add(mod, x11.XK_6, selectTag6),
        add(mod, x11.XK_7, selectTag7),
        add(mod, x11.XK_8, selectTag8),
        add(mod, x11.XK_9, selectTag9),
        add(mod | x11.ShiftMask, x11.XK_1, moveToTag1),
        add(mod | x11.ShiftMask, x11.XK_2, moveToTag2),
        add(mod | x11.ShiftMask, x11.XK_3, moveToTag3),
        add(mod | x11.ShiftMask, x11.XK_4, moveToTag4),
        add(mod | x11.ShiftMask, x11.XK_5, moveToTag5),
        add(mod | x11.ShiftMask, x11.XK_6, moveToTag6),
        add(mod | x11.ShiftMask, x11.XK_7, moveToTag7),
        add(mod | x11.ShiftMask, x11.XK_8, moveToTag8),
        add(mod | x11.ShiftMask, x11.XK_9, moveToTag9),
    };
};
