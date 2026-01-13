const std = @import("std");
const root = @import("root.zig");
const Alignment = std.mem.Alignment;
const Allocator = std.mem.Allocator;

const vtable = Allocator.VTable{
    .alloc = alloc,
    .resize = resize,
    .remap = remap,
    .free = free,
};

fn alloc(_: *anyopaque, len: usize, alignment: Alignment, _: usize) ?[*]u8 {
    return root.vtable.v1.mem_alloc(len, Alignment.toByteUnits(alignment));
}

fn resize(_: *anyopaque, mem: []u8, alignment: Alignment, new_len: usize, _: usize) bool {
    return root.vtable.v1.mem_resize(mem.ptr, mem.len, new_len, Alignment.toByteUnits(alignment));
}

fn remap(_: *anyopaque, mem: []u8, alignment: Alignment, new_len: usize, _: usize) ?[*]u8 {
    return root.vtable.v1.mem_remap(mem.ptr, mem.len, new_len, Alignment.toByteUnits(alignment));
}

fn free(_: *anyopaque, mem: []u8, alignment: Alignment, _: usize) void {
    return root.vtable.v1.mem_free(mem.ptr, mem.len, Alignment.toByteUnits(alignment));
}

pub fn allocator() Allocator {
    return .{ .ptr = @ptrFromInt(1), .vtable = &vtable };
}
