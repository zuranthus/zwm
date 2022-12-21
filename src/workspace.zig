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

        const i = util.findIndex(self.clients.items, client).?;
        const nextIndex = util.nextIndex(self.clients.items, i);
        return self.clients.items[nextIndex];
    }

    pub fn prevClient(self: *Self, client: *Client) *Client {
        std.debug.assert(self.clients.items.len > 0);

        const i = util.findIndex(self.clients.items, client).?;
        const prevIndex = util.prevIndex(self.clients.items, i);
        return self.clients.items[prevIndex];
    }

    pub fn firstTileableClient(self: *Self) ?*Client {
        var i: usize = 0;
        while (i < self.clients.items.len) : (i += 1) {
            if (!self.clients.items[i].is_floating) return self.clients.items[i];
        }
        return null;
    }

    pub fn nextTileableClient(self: *Self, client: *Client) *Client {
        std.debug.assert(self.clients.items.len > 0);
        std.debug.assert(!client.is_floating);

        var i = util.findIndex(self.clients.items, client).?;
        while (true) {
            i = util.nextIndex(self.clients.items, i);
            if (!self.clients.items[i].is_floating) break;
        }
        return self.clients.items[i];
    }

    pub fn prevTileableClient(self: *Self, client: *Client) *Client {
        std.debug.assert(self.clients.items.len > 0);
        std.debug.assert(!client.is_floating);

        var i = util.findIndex(self.clients.items, client).?;
        while (true) {
            i = util.prevIndex(self.clients.items, i);
            if (!self.clients.items[i].is_floating) break;
        }
        return self.clients.items[i];
    }

    pub fn swapClients(self: *Self, client1: *Client, client2: *Client) void {
        std.debug.assert(self.clients.items.len > 0);
        const index1 = util.findIndex(self.clients.items, client1).?;
        const index2 = util.findIndex(self.clients.items, client2).?;
        util.swap(self.clients.items, index1, index2);
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
