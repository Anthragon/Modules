const std = @import("std");
const root = @import("root.zig");
const module_config = @import("module_config");

const Guid = root.Guid;
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

extern fn @"cap callable [00000000-0000-0000-0000-000000000000]System.ModuleHelper::malloc"(module_uuid: Guid, length: usize, alignment: usize) callconv(.c) ?[*]u8;
extern fn @"cap privileged_callable [00000000-0000-0000-0000-000000000000]System.ModuleHelper::malloc"(module_uuid: Guid, length: usize, alignment: usize) callconv(.c) ?[*]u8;
const raw_alloc = switch (module_config.builtin) {
    true => @"cap privileged_callable [00000000-0000-0000-0000-000000000000]System.ModuleHelper::malloc",
    false => @"cap callable [00000000-0000-0000-0000-000000000000]System.ModuleHelper::malloc",
};

extern fn @"cap callable [00000000-0000-0000-0000-000000000000]System.ModuleHelper::mresize"(module_uuid: Guid, old_mem: [*]u8, old_len: usize, new_len: usize, alignment: usize) callconv(.c) bool;
extern fn @"cap privileged_callable [00000000-0000-0000-0000-000000000000]System.ModuleHelper::mresize"(module_uuid: Guid, old_mem: [*]u8, old_len: usize, new_len: usize, alignment: usize) callconv(.c) bool;
const raw_resize = switch (module_config.builtin) {
    true => @"cap privileged_callable [00000000-0000-0000-0000-000000000000]System.ModuleHelper::mresize",
    false => @"cap callable [00000000-0000-0000-0000-000000000000]System.ModuleHelper::mresize",
};

extern fn @"cap callable [00000000-0000-0000-0000-000000000000]System.ModuleHelper::mremap"(module_uuid: Guid, old_mem: [*]u8, old_len: usize, new_len: usize, alignment: usize) callconv(.c) ?[*]u8;
extern fn @"cap privileged_callable [00000000-0000-0000-0000-000000000000]System.ModuleHelper::mremap"(module_uuid: Guid, old_mem: [*]u8, old_len: usize, new_len: usize, alignment: usize) callconv(.c) ?[*]u8;
const raw_remap = switch (module_config.builtin) {
    true => @"cap privileged_callable [00000000-0000-0000-0000-000000000000]System.ModuleHelper::mremap",
    false => @"cap callable [00000000-0000-0000-0000-000000000000]System.ModuleHelper::mremap",
};

extern fn @"cap callable [00000000-0000-0000-0000-000000000000]System.ModuleHelper::mfree"(module_uuid: Guid, mem: [*]u8, len: usize, alignment: usize) callconv(.c) void;
extern fn @"cap privileged_callable [00000000-0000-0000-0000-000000000000]System.ModuleHelper::mfree"(module_uuid: Guid, mem: [*]u8, len: usize, alignment: usize) callconv(.c) void;
const raw_free = switch (module_config.builtin) {
    true => @"cap privileged_callable [00000000-0000-0000-0000-000000000000]System.ModuleHelper::mfree",
    false => @"cap callable [00000000-0000-0000-0000-000000000000]System.ModuleHelper::mfree",
};

const vtable: Allocator.VTable = .{
    .alloc = alloc,
    .resize = resize,
    .remap = remap,
    .free = free,
};

fn alloc(_: *anyopaque, len: usize, alignment: Alignment, _: usize) ?[*]u8 {
    return raw_alloc(root.module_uuid, len, alignment.toByteUnits());
}
fn resize(_: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, _: usize) bool {
    return raw_resize(root.module_uuid, memory.ptr, memory.len, new_len, alignment.toByteUnits());
}
fn remap(_: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, _: usize) ?[*]u8 {
    return raw_remap(root.module_uuid, memory.ptr, memory.len, new_len, alignment.toByteUnits());
}
fn free(_: *anyopaque, memory: []u8, alignment: Alignment, _: usize) void {
    return raw_free(root.module_uuid, memory.ptr, memory.len, alignment.toByteUnits());
}

pub fn allocator() Allocator {
    return .{ .ptr = @ptrFromInt(1), .vtable = &vtable };
}
