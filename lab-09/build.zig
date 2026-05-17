const std = @import("std");
const bsp = @import("nucleo-g071rb");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.resolveTargetQuery(bsp.stm32_target);

    const bsp_dep = b.dependency("nucleo-g071rb", .{
        .optimize = optimize,
    });

    const board_mod = bsp_dep.module("board");

    const exe = b.addExecutable(.{
        .name = "lab-09",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("board", board_mod);
    exe.setLinkerScript(bsp_dep.path("stm32g071rb.ld"));
    exe.root_module.strip = false;
    b.installArtifact(exe);
}
