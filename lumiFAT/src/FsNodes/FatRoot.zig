const std = @import("std");
const core = @import("root").lib;
const FsNode = core.common.FsNode;
const PartEntry = core.common.PartEntry;
const Result = core.interop.Result;


node: FsNode = undefined,
partition_entry: *PartEntry,

pub fn init(allocator: std.mem.Allocator, name: []const u8, entry: *PartEntry) *@This() {

    var this = allocator.create(@This()) catch @import("root").oom_panic();
    const name_copy = allocator.dupeZ(u8, name) catch @import("root").oom_panic();
    this.* = .{ .partition_entry = entry };

    this.node = .{
        .name = name_copy,
        .type = "FAT partition",
        .type_id = "fatfs_root",
        .iterable = true,
        .vtable = &vtable,
    };

    return this;
}
pub fn deinit(allocator: std.mem.Allocator, s: @This()) void {
    allocator.free(s.node.name);
    s.children.deinit();
    allocator.destroy(s);
}

const vtable: FsNode.FsNodeVtable = .{
    .append_node = append,
    .get_child = getchild,
    .branch = branch,
};

// Vtable functions after here

fn append(s: *FsNode, node: *FsNode) callconv(.c) Result(void) {
    const ctx: *@This() = @fieldParentPtr("node", s);

    _ = ctx;
    _ = node;

    @panic("FAT file saving not implemented!");

    //return .retvoid();
}
fn getchild(s: *FsNode, index: usize) callconv(.c) Result(*FsNode) {
    const ctx: *@This() = @fieldParentPtr("node", s);

    std.log.info("Trying to get child at index {}", .{ index });

    _ = ctx;
    //_ = index;

    return .err(.outOfBounds);
}
fn branch(s: *FsNode, path: [*:0]const u8) callconv(.c) Result(*FsNode) {
    const ctx: *@This() = @fieldParentPtr("node", s);

    _ = ctx;
    _ = path;

    return .err(.outOfBounds);
}

