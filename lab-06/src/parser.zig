const std = @import("std");

pub const Command = enum {
    start,
    stop,
    unknown,
};

pub fn parse(input: []const u8) Command {
    if (std.mem.eql(u8, input, "START")) return .start;
    if (std.mem.eql(u8, input, "STOP")) return .stop;
    return .unknown;
}
