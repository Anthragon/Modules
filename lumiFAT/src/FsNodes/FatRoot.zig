const std = @import("std");
const core = @import("root").lib;
const FsNode = core.common.FsNode;
const PartEntry = core.common.PartEntry;
const Result = core.interop.Result;

const FatDirectoryEntry = @import("FatDirectoryEntry.zig");
const fat = @import("../fat.zig");

node: FsNode = undefined,
partition_entry: *const PartEntry,
children: std.StringArrayHashMapUnmanaged(*FatDirectoryEntry) = .empty,
virt_children: std.StringArrayHashMapUnmanaged(*FsNode) = .empty,

pub fn init(allocator: std.mem.Allocator, name: []const u8, entry: *const PartEntry) *@This() {
    var this = allocator.create(@This()) catch @import("root").oom_panic();
    const name_copy = allocator.dupeZ(u8, name) catch @import("root").oom_panic();
    this.* = .{ .partition_entry = entry };

    this.node = .{
        .name = name_copy,
        .type = "FAT partition",
        .type_id = "fatfs_root",
        .iterable = true,
        .physical = true,
        .vtable = &rootvtable,
    };

    return this;
}
pub fn deinit(allocator: std.mem.Allocator, s: *@This()) void {
    allocator.free(s.node.name);
    s.children.deinit();
    allocator.destroy(s);
}

pub fn load_children(s: *@This(), alloc: std.mem.Allocator) void {
    const entries = fat.get_root_directory_entries(alloc, s.partition_entry);
    defer alloc.free(entries);

    var long_name_buf: [256]u16 = undefined;
    var utf8_long_name_buf: [512]u8 = undefined;
    var long_name_idx: usize = 0;

    for (entries) |entry| {
        if (@as(u8, @bitCast(entry.file_attributes)) == 0x0f) {
            long_name_idx += 1;

            const str_idx = 512 - long_name_idx * 26;
            const buf_u8 = @as([*]u8, @ptrCast(&long_name_buf));
            const buf_entry = std.mem.asBytes(&entry);

            @memcpy(buf_u8[str_idx..], buf_entry[0x01..0x0B]); // 5 chars, 10 bytes
            @memcpy(buf_u8[str_idx + 10 ..], buf_entry[0x0E..0x1A]); // 6 chars, 12 bytes
            @memcpy(buf_u8[str_idx + 22 ..], buf_entry[0x1C..0x20]); // 2 chars, 4  bytes
        } else { // Is valid entry

            var long_name: ?[]u8 = null;

            if (long_name_idx > 0) {
                const str_idx = 256 - long_name_idx * 13;
                _ = std.unicode.utf16LeToUtf8(&utf8_long_name_buf, long_name_buf[str_idx..]) catch unreachable;
                long_name = std.mem.sliceTo(&utf8_long_name_buf, 0);
            }
            long_name_idx = 0;

            var name_buf: [12]u8 = undefined;

            if (!entry.is_directory()) {
                const str_name = long_name orelse std.fmt.bufPrint(&name_buf, "{s}.{s}", .{ entry.get_name(), entry.get_extension() }) catch unreachable;

                const start_cluster = entry.get_cluster().?;
                const size = entry.file_size;

                const file_node = FatDirectoryEntry.init_file(
                    alloc,
                    s,
                    str_name,
                    start_cluster,
                    size,
                );
                s.children.put(
                    alloc,
                    std.mem.sliceTo(file_node.node.name, 0),
                    file_node,
                ) catch @import("root").oom_panic();
            } else {
                const str_name = long_name orelse entry.get_name();

                const start_cluster = @as(u32, @intCast(entry.first_cluster_high)) << 16 | entry.first_cluster_low;

                const dir_node = FatDirectoryEntry.init_dir(
                    alloc,
                    s,
                    str_name,
                    start_cluster,
                );
                dir_node.load_children(alloc);
                s.children.put(
                    alloc,
                    std.mem.sliceTo(dir_node.node.name, 0),
                    dir_node,
                ) catch @import("root").oom_panic();
            }
        }
    }
}

const rootvtable: FsNode.FsNodeVtable = .{
    .append_node = append,
    .get_child = getchild,
    .branch = branch,
};

fn append(s: *FsNode, node: *FsNode) callconv(.c) Result(void) {
    const ctx: *@This() = @fieldParentPtr("node", s);

    _ = ctx;
    _ = node;

    @panic("FAT file saving not implemented!");

    //return .retvoid();
}
fn getchild(s: *FsNode, index: usize) callconv(.c) Result(*FsNode) {
    const ctx: *@This() = @fieldParentPtr("node", s);

    const val = ctx.children.values();
    if (index >= val.len) return .err(.outOfBounds);

    return .val(&val[index].node);
}
fn branch(s: *FsNode, path: [*:0]const u8) callconv(.c) Result(*FsNode) {
    const ctx: *@This() = @fieldParentPtr("node", s);

    const pathslice = std.mem.sliceTo(path, 0);
    const i: usize = std.mem.indexOf(u8, pathslice, "/") orelse pathslice.len;
    const nodename = pathslice[0..i];

    var vcdict = ctx.children;
    if (vcdict.contains(nodename)) {
        std.log.info("aaaaaaaaaaaa {s}", .{pathslice});
        const node = vcdict.get(nodename).?;
        if (i != pathslice.len) return node.node.branch(path[i + 1 ..]);
        return .val(&node.node);
    }

    std.log.info("{s} not found", .{pathslice});
    for (ctx.children.keys()) |j| {
        std.log.info("{s}", .{j});
    }

    return .err(.invalidPath);
}
