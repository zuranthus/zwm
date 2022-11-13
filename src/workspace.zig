const std = @import("std");
const util = @import("util.zig");
const Client = @import("client.zig").Client;

pub const Workspace = struct {
    const Self = @This();
    const Clients = std.ArrayList(*Client);

    id: u8,
    clients: Clients,
    active_client: ?*Client = null,

    pub fn init(workspace_id: u8) Self {
        return .{ .id = workspace_id, .clients = Clients.init(std.heap.c_allocator) };
    }

    pub fn deinit(self: *Self) void {
        self.clients.deinit();
    }

    pub fn addClient(self: *Self, client: *Client) void {
        std.debug.assert(client.workspace_id != self.id);
        client.workspace_id = self.id;
        self.clients.insert(0, client) catch @panic("");
        self.active_client = client;
    }

    pub fn activateClient(self: *Self, client: *Client) void {
        if (!util.contains(self.clients.items, client)) @panic("Client is not part of the workspace");
        self.active_client = client;
    }

    pub fn activateNextClient(self: *Self) void {
        if (self.active_client) |client| {
            const i = util.findIndex(self.clients.items, client).?;
            const nextIndex = util.nextIndex(self.clients.items, i);
            self.active_client = self.clients.items[nextIndex];
        }
    }

    pub fn activatePrevClient(self: *Self) void {
        if (self.active_client) |client| {
            const i = util.findIndex(self.clients.items, client).?;
            const prevIndex = util.prevIndex(self.clients.items, i);
            self.active_client = self.clients.items[prevIndex];
        }
    }

    pub fn swapWithNextClient(self: *Self, client: *Client) *Client {
        const i = util.findIndex(self.clients.items, client).?;
        const nextIndex = util.nextIndex(self.clients.items, i);
        util.swap(self.clients.items, i, nextIndex);
        return self.clients.items[i];
    }

    pub fn swapWithPrevClient(self: *Self, client: *Client) *Client {
        const i = util.findIndex(self.clients.items, client).?;
        const prevIndex = util.prevIndex(self.clients.items, i);
        util.swap(self.clients.items, i, prevIndex);
        return self.clients.items[i];
    }

    pub fn swapWithFirst(self: *Self, client: *Client) *Client {
        const i = util.findIndex(self.clients.items, client).?;
        util.swap(self.clients.items, i, 0);
        return self.clients.items[i];
    }

    pub fn removeClient(self: *Self, client: *Client) bool {
        if (util.findIndex(self.clients.items, client)) |i| {
            const c = self.clients.orderedRemove(i);
            std.debug.assert(client == c);
            client.workspace_id = null;
            if (client == self.active_client) {
                // activate next client if the removed was active
                // or activate the last client if the removed active client was last
                const len = self.clients.items.len;
                if (len == 0) {
                    self.active_client = null;
                } else {
                    self.active_client = self.clients.items[if (i == len) len - 1 else i];
                }
            }
            return true;
        }
        return false;
    }
};