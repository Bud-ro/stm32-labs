const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const bsp_dep = b.dependency("nucleo-g071rb", .{ .optimize = optimize });
    const board_mod = bsp_dep.module("board");

    const class_board_mod = b.addModule("class_board", .{
        .root_source_file = b.path("src/class_board.zig"),
        .target = target,
        .optimize = optimize,
    });
    class_board_mod.addImport("board", board_mod);
}
