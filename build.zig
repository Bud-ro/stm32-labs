const std = @import("std");

pub fn build(b: *std.Build) void {
    const explicit_optimize = b.option(std.builtin.OptimizeMode, "optimize", "Optimization mode (default: ReleaseSmall)");
    const optimize = explicit_optimize orelse .ReleaseSmall;
    const lab = b.option([]const u8, "lab", "Which lab to build (e.g. lab-03)") orelse "lab-03";

    const lab_dep = b.dependency(@as([]const u8, lab), .{
        .optimize = optimize,
    });

    const elf = lab_dep.artifact(lab);
    const install_elf = b.addInstallArtifact(elf, .{});

    const bin = elf.addObjCopy(.{ .format = .bin });
    const install_bin = b.addInstallBinFile(bin.getOutput(), b.fmt("{s}.bin", .{lab}));

    // Memory report runs on every build
    const elf_size_dep = b.dependency("zig_pub_sub", .{}).builder.dependency("elf_size", .{});
    const mem_report = b.addRunArtifact(elf_size_dep.artifact("elf-size"));
    mem_report.addFileArg(elf.getEmittedBin());
    mem_report.addArgs(&.{
        "FLASH:08000000:20000",
        "RAM:20000000:9000",
    });
    mem_report.step.dependOn(&install_elf.step);

    b.getInstallStep().dependOn(&install_elf.step);
    b.getInstallStep().dependOn(&install_bin.step);
    b.getInstallStep().dependOn(&mem_report.step);

    const flash = b.addSystemCommand(&.{
        "openocd",
        "-f",
        "interface/stlink.cfg",
        "-f",
        "target/stm32g0x.cfg",
        "-c",
    });
    flash.addArg(b.fmt("program zig-out/bin/{s}.bin 0x08000000 verify reset exit", .{lab}));
    flash.step.dependOn(b.getInstallStep());

    const flash_step = b.step("flash", "Flash to NUCLEO-G071RB via ST-Link");
    flash_step.dependOn(&flash.step);
}
