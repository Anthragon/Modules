const std = @import("std");
pub fn build(b: *std.Build) void {

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core = b.addModule("lumiFAT", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    _ = core;

}
