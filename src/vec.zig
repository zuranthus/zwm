// TODO: get rid fo these
pub const IntVec2 = struct {
    x: i32,
    y: i32,

    pub fn init(x: anytype, y: anytype) IntVec2 {
        return .{ .x = @intCast(i32, x), .y = @intCast(i32, y) };
    }
};
pub const Pos = IntVec2;
pub const Size = IntVec2;
