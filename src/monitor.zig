const std = @import("std");
const Size = @import("vec.zig").Size;
const Workspace = @import("workspace.zig").Workspace;
const Client = @import("client.zig").Client;

pub const Monitor = struct {
    const Self = @This();
    const workspaceCount: u8 = 10;

    size: Size,
    mainSize: f32 = 50.0,
    workspaces: [workspaceCount]Workspace = undefined,
    activeWorkspaceIndex: u8 = 1,

    pub fn init(monitorSize: Size) Self {
        var m = Self{ .size = monitorSize };
        for (m.workspaces) |*w, i| w.* = Workspace.init(@intCast(u8, i));
        return m;
    }

    pub fn deinit(self: *Monitor) void {
        for (self.workspaces) |*w| w.deinit();
    }

    pub fn activateWorkspace(self: *Self, workspaceIndex: u8) void {
        // TODO: allow 0?
        std.debug.assert(1 <= workspaceIndex and workspaceIndex <= workspaceCount);
        self.activeWorkspaceIndex = workspaceIndex;
    }

    pub fn activeWorkspace(self: *Self) *Workspace {
        return &self.workspaces[self.activeWorkspaceIndex];
    }

    pub fn addClient(self: *@This(), client: *Client, workspaceId: ?u8) void {
        std.debug.assert(client.monitorId == null or client.monitorId.? != 0);
        client.monitorId = 0; // TODO: replace with current monitor's id
        const workspace = if (workspaceId) |id| &self.workspaces[id] else self.activeWorkspace();
        workspace.addClient(client);
    }

    pub fn removeClient(self: *@This(), client: *Client) void {
        for (self.workspaces) |*w|
            if (w.removeClient(client)) {
                client.monitorId = null;
            };
    }

    pub fn applyLayout(self: *@This(), layout: anytype) void {
        layout.apply(self.activeWorkspace().clients.items, .{ .x = 0, .y = 0 }, self.size, self.mainSize / 100.0);
    }
};
