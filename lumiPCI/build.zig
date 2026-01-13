const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .os_tag = .freestanding } });
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addModule("lumiPCI_lib", .{
        .root_source_file = b.path("lib/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const klib = b.dependency("klib", .{}).module("klib");

    const core = b.addModule("lumiPCI", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
        .code_model = .kernel,
    });

    core.addImport("lib", lib);
    core.addImport("klib", klib);
}
