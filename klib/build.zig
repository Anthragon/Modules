const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const kernel_lib = b.dependency("kernel", .{}).module("lib");

    const core = b.addModule("klib", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    core.addImport("kernel", kernel_lib);
}
