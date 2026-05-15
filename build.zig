const std = @import("std");

const labs = [_][]const u8{ "lab-03", "lab-04", "lab-05" };

pub fn build(b: *std.Build) void {
    const explicit_optimize = b.option(std.builtin.OptimizeMode, "optimize", "Optimization mode (default: ReleaseSmall)");
    const optimize = explicit_optimize orelse .ReleaseSmall;
    const selected_lab = b.option([]const u8, "lab", "Which lab to build (e.g. lab-03)") orelse "lab-03";

    const elf_size_tool = b.dependency("zig_pub_sub", .{})
        .builder.dependency("elf_size", .{})
        .artifact("elf-size");

    const all_step = b.step("all", "Build every lab and verify its memory report against the committed snapshot");
    const snapshot_step = b.step("snapshot-memory", "Regenerate memory-reports/<lab>.txt from the current build");
    const check_step = b.step("check-memory", "Diff memory-reports/<lab>.txt against the current build");

    var selected_install: ?*std.Build.Step.InstallArtifact = null;
    var selected_install_bin: ?*std.Build.Step = null;

    for (labs) |name| {
        const lab_dep = b.dependency(name, .{ .optimize = optimize });
        const elf = lab_dep.artifact(name);
        const install_elf = b.addInstallArtifact(elf, .{});

        const bin = elf.addObjCopy(.{ .format = .bin });
        const install_bin = b.addInstallBinFile(bin.getOutput(), b.fmt("{s}.bin", .{name}));

        const report = b.addRunArtifact(elf_size_tool);
        report.addFileArg(elf.getEmittedBin());
        report.addArgs(&.{
            "FLASH:08000000:20000",
            "RAM:20000000:9000",
        });
        const report_file = report.captureStdOut(.{});

        const snapshot_rel = b.fmt("memory-reports/{s}.txt", .{name});

        const update_snapshot = b.addUpdateSourceFiles();
        update_snapshot.addCopyFileToSource(report_file, snapshot_rel);
        snapshot_step.dependOn(&update_snapshot.step);

        const check = b.addSystemCommand(&.{ "diff", "-u", "--" });
        check.addFileArg(b.path(snapshot_rel));
        check.addFileArg(report_file);
        check.setName(b.fmt("check-memory ({s})", .{name}));
        check_step.dependOn(&check.step);

        all_step.dependOn(&install_elf.step);
        all_step.dependOn(&install_bin.step);
        all_step.dependOn(&check.step);

        if (std.mem.eql(u8, name, selected_lab)) {
            selected_install = install_elf;
            selected_install_bin = &install_bin.step;
        }
    }

    const install = selected_install orelse {
        std.debug.print("error: unknown -Dlab={s}; expected one of: lab-03, lab-04, lab-05\n", .{selected_lab});
        std.process.exit(1);
    };
    const install_bin = selected_install_bin.?;

    const print_report = b.addRunArtifact(elf_size_tool);
    print_report.addFileArg(install.artifact.getEmittedBin());
    print_report.addArgs(&.{
        "FLASH:08000000:20000",
        "RAM:20000000:9000",
    });
    print_report.step.dependOn(&install.step);

    b.getInstallStep().dependOn(&install.step);
    b.getInstallStep().dependOn(install_bin);
    b.getInstallStep().dependOn(&print_report.step);

    const flash = b.addSystemCommand(&.{
        "openocd",
        "-f",
        "interface/stlink.cfg",
        "-f",
        "target/stm32g0x.cfg",
        "-c",
    });
    flash.addArg(b.fmt("program zig-out/bin/{s}.bin 0x08000000 verify reset exit", .{selected_lab}));
    flash.step.dependOn(b.getInstallStep());

    const flash_step = b.step("flash", "Flash to NUCLEO-G071RB via ST-Link");
    flash_step.dependOn(&flash.step);
}
