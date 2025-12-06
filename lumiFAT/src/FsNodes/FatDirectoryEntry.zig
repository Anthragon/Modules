const std = @import("std");
const core = @import("root").lib;
const fat = @import("../fat.zig");
const FsNode = core.common.FsNode;
const PartEntry = core.common.PartEntry;
const Result = core.interop.Result;

const FatRoot = @import("FatRoot.zig");
const FatContext = fat.FatContex;

const log = std.log.scoped(.@"FAT entry");

uses: usize = 0,
deleted: bool = false,

name: [:0]const u8,
root: *FatRoot,

content: union(enum) {
    file: FatFileContentEntry,
    dir: FatDirContentEntry,
},

const FatDirectoryEntry = @This();

const FatFileContentEntry = struct {
    cluster: usize,
    size: usize,
};
const FatDirContentEntry = struct {
    cluster: usize,
    children: std.StringArrayHashMapUnmanaged(FsNode) = .empty,
};

pub fn init_file(
    allocator: std.mem.Allocator,
    root: *FatRoot,
    name: []const u8,
    start_cluster: usize,
    size: usize,
) *@This() {
    const this = allocator.create(@This()) catch @import("root").oom_panic();
    const name_copy = allocator.dupeZ(u8, name) catch @import("root").oom_panic();
    this.* = .{
        .name = name_copy,
        .root = root,
        .content = .{ .file = .{
            .cluster = start_cluster,
            .size = size,
        } },
    };

    return this;
}
pub fn init_dir(
    allocator: std.mem.Allocator,
    root: *FatRoot,
    name: []const u8,
    start_cluster: usize,
) *@This() {
    const this = allocator.create(@This()) catch @import("root").oom_panic();
    const name_copy = allocator.dupeZ(u8, name) catch @import("root").oom_panic();
    this.* = .{
        .name = name_copy,
        .root = root,
        .content = .{ .dir = .{
            .cluster = start_cluster,
        } },
    };

    return this;
}

pub fn get_node(s: *@This()) FsNode {
    s.uses += 1;
    return switch (s.content) {
        .file => .{
            .context = @ptrCast(s),
            .name = s.name,
            .type = "File",
            .type_id = "fatfs,file",
            .flags = .{
                .iterable = false,
                .physical = true,
                .readable = true,
                .writeable = true,
            },
            .vtable = &file_vtable,
        },
        .dir => .{
            .context = @ptrCast(s),
            .name = s.name,
            .type = "Directory",
            .type_id = "fatfs,dir",
            .flags = .{
                .iterable = true,
                .physical = true,
                .readable = false,
                .writeable = false,
            },
            .vtable = &dir_vtable,
        },
    };
}

pub fn deinit(allocator: std.mem.Allocator, s: @This()) void {
    allocator.free(s.node.name);
    switch (s.content) {
        .dir => |*d| d.children.deinit(allocator),
    }
    allocator.destroy(s);
}

pub fn load_children(s: *@This(), alloc: std.mem.Allocator) void {
    const entries = fat.get_directory_entries(
        alloc,
        s.content.dir.cluster,
        s.root.partition_entry,
    );
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

            if (std.mem.eql(u8, std.mem.trimRight(u8, &entry.name, " "), ".") or std.mem.eql(u8, std.mem.trimRight(u8, &entry.name, " "), "..")) continue;

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

                std.log.debug("Creating file entry {s}", .{str_name});
                const new_file = FatDirectoryEntry.init_file(
                    alloc,
                    s.root,
                    str_name,
                    start_cluster,
                    size,
                );
                s.content.dir.children.put(
                    alloc,
                    std.mem.sliceTo(new_file.name, 0),
                    new_file.get_node(),
                ) catch @import("root").oom_panic();
            } else {
                const str_name = long_name orelse entry.get_name();

                const start_cluster = @as(u32, @intCast(entry.first_cluster_high)) << 16 | entry.first_cluster_low;

                std.log.debug("Creating dir entry {s}", .{str_name});
                const dir_node = FatDirectoryEntry.init_dir(
                    alloc,
                    s.root,
                    str_name,
                    start_cluster,
                );
                dir_node.load_children(alloc);
                s.content.dir.children.put(
                    alloc,
                    std.mem.sliceTo(dir_node.name, 0),
                    dir_node.get_node(),
                ) catch @import("root").oom_panic();
            }
        }
    }
}

const file_vtable: FsNode.FsNodeVtable = .{
    .open = open,
    .close = close,
    .get_size = file__get_size,
    .read = file__read,
};
const dir_vtable: FsNode.FsNodeVtable = .{
    .open = open,
    .close = close,
    .append_node = dir__append,
    .get_child = dir__get_child,
    .branch = dir__branch,
};

fn open(ctx: *anyopaque) callconv(.c) FsNode {
    const s: *@This() = @ptrCast(@alignCast(ctx));
    return s.get_node();
}
fn close(ctx: *anyopaque) callconv(.c) void {
    const s: *@This() = @ptrCast(@alignCast(ctx));
    s.uses -= 1;
}

fn dir__append(ctx: *anyopaque, node: FsNode) callconv(.c) Result(void) {
    const s: *@This() = @ptrCast(@alignCast(ctx));

    _ = s;
    _ = node;

    @panic("FAT file saving not implemented!");

    //return .retvoid();
}
fn dir__get_child(ctx: *anyopaque, index: usize) callconv(.c) Result(FsNode) {
    var s: *@This() = @ptrCast(@alignCast(ctx));

    if (index >= s.content.dir.children.count()) return .err(.outOfBounds);
    const children = s.content.dir.children.values();
    return .val(children[index].open());
}
fn dir__branch(ctx: *anyopaque, path: [*:0]const u8) callconv(.c) Result(FsNode) {
    const s: *@This() = @ptrCast(@alignCast(ctx));

    const pathslice = std.mem.sliceTo(path, 0);
    const i: usize = std.mem.indexOf(u8, pathslice, "/") orelse pathslice.len;
    const nodename = pathslice[0..i];

    var cdict = s.content.dir.children;
    if (cdict.contains(nodename)) {
        const node = cdict.get(nodename).?;
        if (i != pathslice.len) return node.branch(path[i + 1 ..]);
        return .val(node.open());
    }

    return .err(.notFound);
}

fn file__get_size(ctx: *anyopaque) callconv(.c) Result(usize) {
    const s: *@This() = @ptrCast(@alignCast(ctx));
    return .val(s.content.file.size);
}
fn file__read(ctx: *anyopaque, buffer: [*]u8, len: usize) callconv(.c) Result(usize) {
    const s: *@This() = @ptrCast(@alignCast(ctx));
    const start = s.content.file.cluster;

    const buf = buffer[0..len];
    const bytes_written = fat.read_file(start, buf, s.root.partition_entry);

    return .val(bytes_written);
}
