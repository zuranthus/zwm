const std = @import("std");
const util = @import("util.zig");
const Pos = util.Pos;
const Size = util.Size;
const Workspace = @import("workspace.zig").Workspace;
const Client = @import("client.zig").Client;

pub const Monitor = struct {
    const Self = @This();
    const workspace_count: u8 = 9;

    screen_origin: Pos,
    screen_size: Size,
    origin: Pos,
    size: Size,
    main_size: f32 = 50.0,
    workspaces: [workspace_count]Workspace = undefined,
    id: u8 = 0, // TODO: update when multi-monitor
    active_workspace_id: u8 = 0,

    pub fn init(monitor_origin: Pos, monitor_size: Size) Self {
        var m = Self{
            .screen_origin = monitor_origin,
            .screen_size = monitor_size,
            .origin = monitor_origin,
            .size = monitor_size,
        };
        for (m.workspaces) |*w, i| w.* = Workspace.init(@intCast(u8, i));
        return m;
    }

    pub fn deinit(self: *Self) void {
        for (self.workspaces) |*w| w.deinit();
    }

    pub fn activateWorkspace(self: *Self, workspace_id: u8) void {
        std.debug.assert(0 <= workspace_id and workspace_id < workspace_count);
        self.active_workspace_id = workspace_id;
    }

    pub fn applyStruts(self: *Self, struts: util.Struts) void {
        self.origin.x = self.screen_origin.x + struts.left;
        self.origin.y = self.screen_origin.y + struts.top;
        self.size.x = self.screen_size.x - (struts.left + struts.right);
        self.size.y = self.screen_size.y - (struts.top + struts.bottom);
    }

    pub fn activeWorkspace(self: *Self) *Workspace {
        return &self.workspaces[self.active_workspace_id];
    }

    pub fn addClient(self: *Self, client: *Client, workspace_id: ?u8) void {
        std.debug.assert(client.monitor_id == null or client.monitor_id.? != 0);
        client.monitor_id = 0; // TODO: replace with current monitor's id
        const workspace = if (workspace_id) |id| &self.workspaces[id] else self.activeWorkspace();
        workspace.addClient(client);
    }

    pub fn removeClient(self: *Self, client: *Client) void {
        for (self.workspaces) |*w|
            if (w.removeClient(client)) {
                client.monitor_id = null;
            };
    }

    pub fn applyLayout(self: *Self, layout: anytype) void {
        layout.apply(self.activeWorkspace().clients.items, self.origin, self.size, self.main_size / 100.0);
    }
};
