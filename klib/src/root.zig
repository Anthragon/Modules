const std = @import("std");
const kernel = @import("kernel");

pub const Result = kernel.interop.Result;

pub const Module = extern struct {
    name: [*:0]const u8,
    version: [*:0]const u8,
    author: [*:0]const u8,
    license: [*:0]const u8,
    flags: packed struct {
        needs_privilege: bool,
        _rsvd: u63 = 0,
    },
    uuid: u128,
};

pub const KernelTablev1 = extern struct {
    kernel_name: [*:0]const u8,
    kernel_version: [*:0]const u8,

    log_debug: *const fn ([*:0]const u8) callconv(.c) void,
    log_err: *const fn ([*:0]const u8) callconv(.c) void,
    log_info: *const fn ([*:0]const u8) callconv(.c) void,
    log_warn: *const fn ([*:0]const u8) callconv(.c) void,

    mem_pageSize: usize,
    mem_alloc: *const fn (length: usize, alignment: std.mem.Alignment) callconv(.c) ?[*]u8,
    mem_resize: *const fn (memory: *anyopaque, old_lemgth: usize, new_length: usize, alignment: std.mem.Alignment) callconv(.c) bool,
    mem_remap: *const fn (memory: *anyopaque, old_length: usize, new_length: usize, alignment: std.mem.Alignment) callconv(.c) ?[*]u8,
    mem_free: *const fn (memory: *anyopaque, alignment: std.mem.Alignment) callconv(.c) void,

    capabilities_getNode: *const fn (path: [*:0]const u8) callconv(.c) ?*capabilities.Node,
    capabilities_createResource: *const fn (parent: ?*capabilities.Node, name: [*:0]const u8) callconv(.c) ?*capabilities.Node,
    capabilities_createCallable: *const fn (parent: ?*capabilities.Node, name: [*:0]const u8, callable: *const anyopaque) callconv(.c) Result(*capabilities.Node),
    capabilities_createProperty: *const fn (parent: ?*capabilities.Node, name: [*:0]const u8, getter: *const anyopaque, setter: *const anyopaque) callconv(.c) Result(*capabilities.Node),
    capabilities_createEvent: *const fn (parent: ?*capabilities.Node, name: [*:0]const u8, bind: *const anyopaque, unbind: *const anyopaque) callconv(.c) Result(*capabilities.Node),
};
const KernelTableCallv1 = extern struct {
    version: usize = 1,
    table_ptr: *KernelTablev1,
};

pub const mem = @import("mem.zig");
pub const capabilities = @import("capabilities.zig");
pub const utils = @import("utils/utils.zig");

pub fn get_kernel_table(tablePtr: *KernelTablev1) void {
    const request = KernelTableCallv1{
        .table_ptr = tablePtr,
    };

    asm volatile (
        \\ syscall
        :
        : [rax] "{rax}" (0x000A_0000),
          [rbx] "{rbx}" (&request),
        : .{
          .rcx = true,
          .r11 = true,
          .memory = true,
        });
}
