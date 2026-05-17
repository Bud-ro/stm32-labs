const std = @import("std");

pub const Command = enum {
    start,
    stop,
    temp,
    clear,
    unknown,
};

pub fn parse(input: []const u8) Command {
    if (std.mem.eql(u8, input, "START")) return .start;
    if (std.mem.eql(u8, input, "STOP")) return .stop;
    if (std.mem.eql(u8, input, "TEMP")) return .temp;
    if (std.mem.eql(u8, input, "CLEAR")) return .clear;
    return .unknown;
}
