const std = @import("std");
const kernel = @import("kernel");
pub const module_config = @import("module_config");
const core = @import("core.zig");

pub const std_oprions = std.Options{ .logFn = log };
pub var module_uuid: Guid = undefined;

pub const Module = kernel.common.Module;
pub const Result = kernel.interop.Result;
pub const Guid = kernel.utils.Guid;
pub const Toml = kernel.Toml;
pub const units = kernel.utils.units;
pub const common = kernel.common;
pub const Privilege = kernel.Privilege;

pub const mem = @import("mem.zig");
pub const debug = @import("debug.zig");
pub const devices = @import("devices.zig");

pub const register_cap_call = core.buildin_register_capability_callable;

pub fn kernel_panic(message: [*:0]const u8) noreturn {
    core.panic(module_uuid, message);
    unreachable;
}

fn log(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const str = std.fmt.allocPrint(mem.allocator(), format, args) catch unreachable;
    defer mem.allocator().free(str);
    const scopestr: [*:0]const u8 = @tagName(scope);

    switch (message_level) {
        .info => core.log_info(module_uuid, scopestr, str.ptr, str.len),
        .debug => core.log_debug(module_uuid, scopestr, str.ptr, str.len),
        .err => core.log_err(module_uuid, scopestr, str.ptr, str.len),
        .warn => core.log_warn(module_uuid, scopestr, str.ptr, str.len),
    }
}
