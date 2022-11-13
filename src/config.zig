const x11 = @import("x11.zig");
const api = @import("hotkeys.zig");

pub const modKey = x11.Mod1Mask;
pub const hotkeys = .{
    .{ modKey | x11.ShiftMask, x11.XK_C, api.killFocused, .{} },
    .{ modKey, x11.XK_J, api.focusNext, .{} },
    .{ modKey, x11.XK_K, api.focusPrev, .{} },
    .{ modKey, x11.XK_H, api.decMaster, .{} },
    .{ modKey, x11.XK_L, api.incMaster, .{} },
    .{ modKey, x11.XK_Return, api.swapMain, .{} },
    .{ modKey | x11.ShiftMask, x11.XK_J, api.moveNext, .{} },
    .{ modKey | x11.ShiftMask, x11.XK_K, api.movePrev, .{} },

    .{ modKey, x11.XK_1, api.selectTag, .{1} },
    .{ modKey, x11.XK_2, api.selectTag, .{2} },
    .{ modKey, x11.XK_3, api.selectTag, .{3} },
    .{ modKey, x11.XK_4, api.selectTag, .{4} },
    .{ modKey, x11.XK_5, api.selectTag, .{5} },
    .{ modKey, x11.XK_6, api.selectTag, .{6} },
    .{ modKey, x11.XK_7, api.selectTag, .{7} },
    .{ modKey, x11.XK_8, api.selectTag, .{8} },
    .{ modKey, x11.XK_9, api.selectTag, .{9} },
    .{ modKey | x11.ShiftMask, x11.XK_1, api.moveToTag, .{1} },
    .{ modKey | x11.ShiftMask, x11.XK_2, api.moveToTag, .{2} },
    .{ modKey | x11.ShiftMask, x11.XK_3, api.moveToTag, .{3} },
    .{ modKey | x11.ShiftMask, x11.XK_4, api.moveToTag, .{4} },
    .{ modKey | x11.ShiftMask, x11.XK_5, api.moveToTag, .{5} },
    .{ modKey | x11.ShiftMask, x11.XK_6, api.moveToTag, .{6} },
    .{ modKey | x11.ShiftMask, x11.XK_7, api.moveToTag, .{7} },
    .{ modKey | x11.ShiftMask, x11.XK_8, api.moveToTag, .{8} },
    .{ modKey | x11.ShiftMask, x11.XK_9, api.moveToTag, .{9} },
};