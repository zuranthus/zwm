const std = @import("std");
const util = @import("util.zig");
const Client = @import("client.zig").Client;

pub const Workspace = struct {
    const Self = @This();
    const Clients = std.ArrayList(*Client);

    id: u8,
    clients: Clients,

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
    }

    pub fn nextClient(self: *Self, client: *Client) *Client {
        std.debug.assert(self.clients.items.len > 0);
        std.debug.assert(util.contains(self.clients.items, client));

        const i = util.findIndex(self.clients.items, client).?;
        const nextIndex = util.nextIndex(self.clients.items, i);
        return self.clients.items[nextIndex];
    }

    pub fn prevClient(self: *Self, client: *Client) *Client {
        std.debug.assert(self.clients.items.len > 0);
        std.debug.assert(util.contains(self.clients.items, client));

        const i = util.findIndex(self.clients.items, client).?;
        const prevIndex = util.prevIndex(self.clients.items, i);
        return self.clients.items[prevIndex];
    }

    pub fn swapWithNextClient(self: *Self, client: *Client) *Client {
        const i = util.findIndex(self.clients.items, client).?;
        var nextIndex = i;
        while (true) {
            nextIndex = util.nextIndex(self.clients.items, nextIndex);
            if (nextIndex == i or !self.clients.items[nextIndex].is_floating) break;
        }
        util.swap(self.clients.items, i, nextIndex);
        return self.clients.items[i];
    }

    pub fn swapWithPrevClient(self: *Self, client: *Client) *Client {
        const i = util.findIndex(self.clients.items, client).?;
        var prevIndex = i;
        while (true) {
            prevIndex = util.prevIndex(self.clients.items, prevIndex);
            if (prevIndex == i or !self.clients.items[prevIndex].is_floating) break;
        }
        util.swap(self.clients.items, i, prevIndex);
        return self.clients.items[i];
    }

    pub fn swapWithFirstClient(self: *Self, client: *Client) *Client {
        const i = util.findIndex(self.clients.items, client).?;
        // TODO: replace 0 with the index of the first non-floating client
        util.swap(self.clients.items, i, 0);
        return self.clients.items[i];
    }

    pub fn removeClient(self: *Self, client: *Client) bool {
        if (util.findIndex(self.clients.items, client)) |i| {
            const c = self.clients.orderedRemove(i);
            std.debug.assert(client == c);
            client.workspace_id = null;
            return true;
        }
        return false;
    }
};