const std = @import("std");

pub const Command = union(enum) {
    duty: u8,
    halt,
    unknown,
};

pub fn parse(input: []const u8) Command {
    if (std.mem.eql(u8, input, "HALT")) return .halt;
    if (std.mem.startsWith(u8, input, "DUTY")) {
        const tail = input[4..];
        if (tail.len == 0 or tail.len > 3) return .unknown;
        var value: u32 = 0;
        for (tail) |c| {
            if (c < '0' or c > '9') return .unknown;
            value = value * 10 + (c - '0');
        }
        if (value > 100) return .unknown;
        return .{ .duty = @intCast(value) };
    }
    return .unknown;
}
