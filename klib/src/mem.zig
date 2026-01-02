const std = @import("std");
const root = @import("root.zig");
const Alignment = std.mem.Alignment;
const Allocator = std.mem.Allocator;

pub const ModuleAllocator = struct {
    const vtable = Allocator.VTable{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    };

    malloc: *const fn (length: usize, alignment: std.mem.Alignment) callconv(.c) ?[*]u8,
    mresize: *const fn (memory: *anyopaque, old_lemgth: usize, new_length: usize, alignment: std.mem.Alignment) callconv(.c) bool,
    mremap: *const fn (memory: *anyopaque, old_length: usize, new_length: usize, alignment: std.mem.Alignment) callconv(.c) ?[*]u8,
    mfree: *const fn (memory: *anyopaque, length: usize, alignment: std.mem.Alignment) callconv(.c) void,

    fn alloc(self: *anyopaque, len: usize, alignment: Alignment, _: usize) ?[*]u8 {
        const s = @as(*ModuleAllocator, @ptrCast(@alignCast(self)));
        return s.malloc(len, alignment);
    }

    fn resize(self: *anyopaque, mem: []u8, alignment: Alignment, new_len: usize, _: usize) bool {
        const s = @as(*ModuleAllocator, @ptrCast(@alignCast(self)));
        return s.mresize(mem, mem.len, new_len, alignment);
    }

    fn remap(self: *anyopaque, mem: []u8, alignment: Alignment, new_len: usize, _: usize) ?[*]u8 {
        const s = @as(*ModuleAllocator, @ptrCast(@alignCast(self)));
        return s.remap(mem, mem.len, new_len, alignment);
    }

    fn free(self: *anyopaque, mem: []u8, alignment: Alignment, _: usize) void {
        const s = @as(*ModuleAllocator, @ptrCast(@alignCast(self)));
        return s.mfree(mem, mem.len, alignment);
    }

    pub fn fromKernelVtable(kvtbl: *const root.KernelTablev1) @This() {
        return .{
            .malloc = kvtbl.mem_alloc,
            .mresize = kvtbl.mem_resize,
            .mremap = kvtbl.mem_remap,
            .mfree = kvtbl.mem_free,
        };
    }
    pub fn allocator(self: @This()) Allocator {
        return .{ .ptr = self, .vtable = vtable };
    }
};
