const std = @import("std");
pub fn build(b: *std.Build) void {

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const pci_dependency = b.dependency("lumiPCI", .{});
    const pci_lib = pci_dependency.module("lumiPCI_lib");

    const core = b.addModule("lumiAHCI", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    core.addImport("pci_lib", pci_lib);

}
