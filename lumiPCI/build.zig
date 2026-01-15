const std = @import("std");
const zig_builtin = @import("builtin");
const Target = std.Target;

pub fn build(b: *std.Build) void {
    const target_arch = b.option(Target.Cpu.Arch, "tarch", "Target archtecture") orelse zig_builtin.cpu.arch;
    const builtin = b.option(bool, "builtin", "activates builtin mode") orelse false;

    const optimize = b.standardOptimizeOption(.{});

    var core_target = Target.Query{
        .cpu_arch = target_arch,
        .os_tag = .freestanding,
        .abi = .none,
        .ofmt = .elf,
    };
    switch (target_arch) {
        .x86_64 => {
            const Feature = std.Target.x86.Feature;

            core_target.cpu_features_sub.addFeature(@intFromEnum(Feature.sse));
            core_target.cpu_features_sub.addFeature(@intFromEnum(Feature.sse2));
            core_target.cpu_features_sub.addFeature(@intFromEnum(Feature.avx));
            core_target.cpu_features_sub.addFeature(@intFromEnum(Feature.avx2));

            core_target.cpu_features_add.addFeature(@intFromEnum(Feature.soft_float));
        },
        .aarch64 => {
            const features = std.Target.aarch64.Feature;
            core_target.cpu_features_sub.addFeature(@intFromEnum(features.fp_armv8));
            core_target.cpu_features_sub.addFeature(@intFromEnum(features.crypto));
            core_target.cpu_features_sub.addFeature(@intFromEnum(features.neon));
        },
        else => std.debug.panic("Unsuported archtecture {s}!", .{@tagName(target_arch)}),
    }
    const target = b.resolveTargetQuery(core_target);

    const lib = b.addModule("lumiPCI_lib", .{
        .root_source_file = b.path("lib/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const klib = b.dependency("klib", .{ .builtin = builtin }).module("klib");

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
