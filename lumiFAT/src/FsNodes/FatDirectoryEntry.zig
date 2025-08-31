const std = @import("std");
const core = @import("root").lib;
const fat = @import("../fat.zig");
const FsNode = core.common.FsNode;
const PartEntry = core.common.PartEntry;
const Result = core.interop.Result;

const FatRoot = @import("FatRoot.zig");
const FatContext = fat.FatContex;

node: FsNode = undefined,
root: *FatRoot,
content: union(enum) {
    file: FatFileEntry,
    dir: FatDirectoryEntry,
},

const FatFileEntry = struct {
    cluster: usize,
};
const FatDirectoryEntry = struct {
    cluster: usize,
    children: std.StringArrayHashMapUnmanaged(*FatDirectoryEntry) = .empty,
};


pub fn init_file(
    allocator: std.mem.Allocator,
    root: *FatRoot,
    name: []const u8,
    start_cluster: *PartEntry
) *@This() {

    var this = allocator.create(@This()) catch @import("root").oom_panic();
    const name_copy = allocator.dupeZ(u8, name) catch @import("root").oom_panic();
    this.* = .{
        .root = root,
        .content = .{ .file = .{ .cluster = start_cluster } },
    };

    this.node = .{
        .name = name_copy,
        .type = "File",
        .type_id = "fatfs_file",
        .iterable = false,
        .vtable = &file_vtable,
    };

    return this;
}
pub fn init_dir(
    allocator: std.mem.Allocator,
    root: *FatRoot,
    name: []const u8,
    start_cluster: *PartEntry
) *@This() {

    var this = allocator.create(@This()) catch @import("root").oom_panic();
    const name_copy = allocator.dupeZ(u8, name) catch @import("root").oom_panic();
    this.* = .{
        .root = root,
        .content = .{ .dir = .{ .cluster = start_cluster } },
    };

    this.node = .{
        .name = name_copy,
        .type = "Directory",
        .type_id = "fatfs_directory",
        .iterable = true,
        .vtable = &dir_vtable,
    };

    return this;
}

pub fn deinit(allocator: std.mem.Allocator, s: @This()) void {
    allocator.free(s.node.name);
    switch (s.content) {
        .dir => |*d| d.children.deinit(allocator),
    }
    allocator.destroy(s);
}

const file_vtable: FsNode.FsNodeVtable = .{};
const dir_vtable: FsNode.FsNodeVtable = .{
    .append_node = dir_append,
    .get_child = dir_get_child,
    .branch = dir_branch,
};

fn dir_append(s: *FsNode, node: *FsNode) callconv(.c) Result(void) {
    const ctx: *@This() = @fieldParentPtr("node", s);

    _ = ctx;
    _ = node;

    @panic("FAT file saving not implemented!");

    //return .retvoid();
}
fn dir_get_child(s: *FsNode, index: usize) callconv(.c) Result(*FsNode) {
    const ctx: *@This() = @fieldParentPtr("node", s);

    std.log.info("Trying to get child at index {}", .{ index });

    _ = ctx;
    //_ = index;

    return .err(.outOfBounds);
}
fn dir_branch(s: *FsNode, path: [*:0]const u8) callconv(.c) Result(*FsNode) {
    const ctx: *@This() = @fieldParentPtr("node", s);

    _ = ctx;
    _ = path;

    return .err(.outOfBounds);
}
