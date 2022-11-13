const x11 = @import("x11.zig");
const api = @import("hotkeys.zig");

pub const border = struct {
    pub const width = 3;
    pub const gap = 5;
    pub const color_normal = 0x808080;
    pub const color_focused = 0xff8000;
};

pub const mod_key = x11.Mod1Mask;
pub const hotkeys = .{
    .{ mod_key, x11.XK_H, api.decMaster, .{} },
    .{ mod_key, x11.XK_L, api.incMaster, .{} },

    .{ mod_key, x11.XK_J, api.focusNext, .{} },
    .{ mod_key, x11.XK_K, api.focusPrev, .{} },
    .{ mod_key | x11.ShiftMask, x11.XK_J, api.moveNext, .{} },
    .{ mod_key | x11.ShiftMask, x11.XK_K, api.movePrev, .{} },
    .{ mod_key, x11.XK_Return, api.swapMain, .{} },

    .{ mod_key | x11.ShiftMask, x11.XK_Return, api.spawn, .{"alacritty"} },

    .{ mod_key | x11.ShiftMask, x11.XK_C, api.killFocused, .{} },

    .{ mod_key, x11.XK_1, api.selectTag, .{1} },
    .{ mod_key, x11.XK_2, api.selectTag, .{2} },
    .{ mod_key, x11.XK_3, api.selectTag, .{3} },
    .{ mod_key, x11.XK_4, api.selectTag, .{4} },
    .{ mod_key, x11.XK_5, api.selectTag, .{5} },
    .{ mod_key, x11.XK_6, api.selectTag, .{6} },
    .{ mod_key, x11.XK_7, api.selectTag, .{7} },
    .{ mod_key, x11.XK_8, api.selectTag, .{8} },
    .{ mod_key, x11.XK_9, api.selectTag, .{9} },
    .{ mod_key | x11.ShiftMask, x11.XK_1, api.moveToTag, .{1} },
    .{ mod_key | x11.ShiftMask, x11.XK_2, api.moveToTag, .{2} },
    .{ mod_key | x11.ShiftMask, x11.XK_3, api.moveToTag, .{3} },
    .{ mod_key | x11.ShiftMask, x11.XK_4, api.moveToTag, .{4} },
    .{ mod_key | x11.ShiftMask, x11.XK_5, api.moveToTag, .{5} },
    .{ mod_key | x11.ShiftMask, x11.XK_6, api.moveToTag, .{6} },
    .{ mod_key | x11.ShiftMask, x11.XK_7, api.moveToTag, .{7} },
    .{ mod_key | x11.ShiftMask, x11.XK_8, api.moveToTag, .{8} },
    .{ mod_key | x11.ShiftMask, x11.XK_9, api.moveToTag, .{9} },
};
