const std = @import("std");
const kernel = @import("kernel");

pub const Result = kernel.interop.Result;

pub const Module = extern struct {
    name: [*:0]const u8,
    version: [*:0]const u8,
    author: [*:0]const u8,
    license: [*:0]const u8,
    uuid: u128,

    vtable: *KernelVTable,
    flags: packed struct {
        needs_privilege: bool,
        _rsvd: u63 = 0,
    },

    init: *const anyopaque,
    deinit: *const anyopaque,
};

pub const KernelVTable = extern struct {
    abi_version: usize,
    kernel_name: [*:0]const u8 = undefined,
    kernel_version: [*:0]const u8 = undefined,
    v1: extern struct {
        panic: *const fn (message: [*:0]const u8) callconv(.c) noreturn,

        log_debug: *const fn (scope: [*:0]const u8, message: [*:0]const u8) callconv(.c) void,
        log_err: *const fn (scope: [*:0]const u8, message: [*:0]const u8) callconv(.c) void,
        log_info: *const fn (scope: [*:0]const u8, message: [*:0]const u8) callconv(.c) void,
        log_warn: *const fn (scope: [*:0]const u8, message: [*:0]const u8) callconv(.c) void,

        mem_pageSize: usize,
        mem_alloc: *const fn (length: usize, alignment: usize) callconv(.c) ?[*]u8,
        mem_resize: *const fn (memory: *anyopaque, old_lemgth: usize, new_length: usize, alignment: usize) callconv(.c) bool,
        mem_remap: *const fn (memory: *anyopaque, old_length: usize, new_length: usize, alignment: usize) callconv(.c) ?[*]u8,
        mem_free: *const fn (memory: *anyopaque, length: usize, alignment: usize) callconv(.c) void,

        capabilities_getNode: *const fn (path: [*:0]const u8) callconv(.c) ?*capabilities.Node,
        capabilities_createResource: *const fn (parent: ?*capabilities.Node, name: [*:0]const u8) callconv(.c) ?*capabilities.Node,
        capabilities_createCallable: *const fn (parent: ?*capabilities.Node, name: [*:0]const u8, callable: *const anyopaque) callconv(.c) Result(*capabilities.Node),
        capabilities_createProperty: *const fn (parent: ?*capabilities.Node, name: [*:0]const u8, getter: *const anyopaque, setter: *const anyopaque) callconv(.c) Result(*capabilities.Node),
        capabilities_createEvent: *const fn (parent: ?*capabilities.Node, name: [*:0]const u8, bind: *const anyopaque, unbind: *const anyopaque) callconv(.c) Result(*capabilities.Node),
    } = undefined,
};

pub const mem = @import("mem.zig");
pub const capabilities = @import("capabilities.zig");
pub const utils = @import("utils/utils.zig");

pub const std_oprions = std.Options{ .logFn = log };
pub var vtable: *KernelVTable = undefined;

pub fn kernel_panic(message: [*:0]const u8) noreturn {
    vtable.v1.panic(message);
    unreachable;
}

fn log(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    var buf: [512]u8 = undefined;
    const str = std.fmt.bufPrintZ(&buf, format, args) catch unreachable;
    const scopestr: [*:0]const u8 = @tagName(scope);

    switch (message_level) {
        .info => vtable.v1.log_info(scopestr, str.ptr),
        .debug => vtable.v1.log_debug(scopestr, str.ptr),
        .err => vtable.v1.log_err(scopestr, str.ptr),
        .warn => vtable.v1.log_warn(scopestr, str.ptr),
    }
}
