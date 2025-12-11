const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const pci_lib = b.dependency("lumiPCI", .{}).module("lumiPCI_lib");
    const disk_lib = b.dependency("lumiDisk", .{}).module("lumiDisk_lib");

    const core = b.addModule("lumiAHCI", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    core.addImport("pci_lib", pci_lib);
    core.addImport("disk_lib", disk_lib);
}
