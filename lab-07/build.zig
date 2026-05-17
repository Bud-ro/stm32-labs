const std = @import("std");
const bsp = @import("nucleo-g071rb");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.resolveTargetQuery(bsp.stm32_target);

    const bsp_dep = b.dependency("nucleo-g071rb", .{
        .optimize = optimize,
    });
    const common_dep = b.dependency("common", .{
        .target = target,
        .optimize = optimize,
    });
    const class_board_dep = b.dependency("class_board", .{
        .target = target,
        .optimize = optimize,
    });
    const erd_core_dep = b.dependency("zig_pub_sub", .{}).builder.dependency("erd_core", .{
        .target = target,
        .optimize = optimize,
    });

    const board_mod = bsp_dep.module("board");
    const common_mod = common_dep.module("common");
    const class_board_mod = class_board_dep.module("class_board");
    const erd_core_mod = erd_core_dep.module("erd_core");

    const app_mod = b.createModule(.{
        .root_source_file = b.path("src/application.zig"),
        .target = target,
        .optimize = optimize,
    });
    app_mod.addImport("board", board_mod);
    app_mod.addImport("common", common_mod);
    app_mod.addImport("class_board", class_board_mod);
    app_mod.addImport("erd_core", erd_core_mod);

    const exe = b.addExecutable(.{
        .name = "lab-07",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("board", board_mod);
    exe.root_module.addImport("common", common_mod);
    exe.root_module.addImport("class_board", class_board_mod);
    exe.root_module.addImport("erd_core", erd_core_mod);
    exe.root_module.addImport("application", app_mod);
    exe.setLinkerScript(bsp_dep.path("stm32g071rb.ld"));
    exe.root_module.strip = false;
    b.installArtifact(exe);
}
