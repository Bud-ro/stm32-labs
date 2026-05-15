const std = @import("std");

pub const stm32_target: std.Target.Query = .{
    .cpu_arch = .thumb,
    .os_tag = .freestanding,
    .abi = .eabi,
    .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m0plus },
};

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(stm32_target);
    const optimize = b.standardOptimizeOption(.{});

    _ = addBoardModule(b, target, optimize);
}

pub fn addBoardModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    const board_mod = b.addModule("board", .{
        .root_source_file = b.path("src/board.zig"),
        .target = target,
        .optimize = optimize,
    });
    return board_mod;
}
