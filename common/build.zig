const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const erd_core_dep = b.dependency("zig_pub_sub", .{}).builder.dependency("erd_core", .{
        .target = target,
        .optimize = optimize,
    });

    const mod = b.addModule("common", .{
        .root_source_file = b.path("src/common.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("erd_core", erd_core_dep.module("erd_core"));
}
