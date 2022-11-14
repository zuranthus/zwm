const log = @import("log.zig");
const config = @import("config.zig");
const vec = @import("vec.zig");
const Pos = vec.Pos;
const Size = vec.Size;
const Client = @import("client.zig").Client;

pub const TileLayout = struct {
    pub fn apply(clients: []const *Client, origin: Pos, size: Size, main_factor: f32) void {
        log.trace("Applying layout to {} clients", .{clients.len});

        if (clients.len == 0) return;
        const gap = config.border.gap;
        var pos = Pos.init(origin.x + gap, origin.y + gap);

        if (clients.len == 1) {
            const main_size = Size.init(size.x - 2 * gap, size.y - 2 * gap);
            clients[0].moveResize(pos, main_size);
            return;
        }

        const msize = Size.init(
            @floatToInt(i32, @intToFloat(f32, size.x) * main_factor - @intToFloat(f32, gap) * 1.5),
            size.y - 2 * gap,
        );
        clients[0].moveResize(pos, msize);
        pos.x += msize.x + gap;
        const ssize = Size.init(
            size.x - msize.x - 3 * gap,
            @divTrunc(size.y - gap, @intCast(i32, clients.len) - 1) - gap,
        );
        for (clients[1..]) |c| {
            c.moveResize(pos, ssize);
            pos.y += ssize.y + gap;
        }
    }
};