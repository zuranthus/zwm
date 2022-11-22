const log = @import("log.zig");
const config = @import("config.zig");
const vec = @import("vec.zig");
const Pos = vec.Pos;
const Size = vec.Size;
const Client = @import("client.zig").Client;

pub const TileLayout = struct {
    pub fn apply(clients: []const *Client, origin: Pos, size: Size, main_factor: f32) void {
        const len = countTileable(clients);
        log.trace("Applying layout to {} clients", .{len});
        if (len == 0) return;

        const gap = config.border.gap;
        var pos = Pos.init(origin.x + gap, origin.y + gap);
        var i: usize = nextTileableClient(clients, 0);

        if (len == 1) {
            const main_size = Size.init(size.x - 2 * gap, size.y - 2 * gap);
            clients[i].moveResize(pos, main_size);
            return;
        }

        const msize = Size.init(
            @floatToInt(i32, @intToFloat(f32, size.x) * main_factor - @intToFloat(f32, gap) * 1.5),
            size.y - 2 * gap,
        );
        clients[i].moveResize(pos, msize);
        pos.x += msize.x + gap;
        const ssize = Size.init(
            size.x - msize.x - 3 * gap,
            @divTrunc(size.y - gap, @intCast(i32, len) - 1) - gap,
        );
        while (true) {
            i = nextTileableClient(clients, i + 1);
            if (i >= clients.len) break;
            clients[i].moveResize(pos, ssize);
            pos.y += ssize.y + gap;
        }
    }
};

fn countTileable(clients: []const *Client) usize {
    var count: usize = 0;
    for (clients) |c| {
        if (!c.is_floating) count += 1;
    }
    return count;
}

fn nextTileableClient(clients: []const *Client, next_i: usize) usize {
    var i = next_i;
    while (i < clients.len) : (i += 1) {
        if (!clients[i].is_floating) break;
    }
    return i;
}