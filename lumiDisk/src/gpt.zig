const std = @import("std");
const root = @import("root");
const lib = @import("lib");
const main = @import("main.zig");

const log = std.log.scoped(.@"lumiDisk GPT");

const fs = root.fs;
const FsNode = fs.FsNode;

const DiskEntry = lib.DiskEntry;
const PartitionEntry = lib.PartitionEntry;
const Guid = root.utils.Guid;

const allocator = root.os.heap.kernel_buddy_allocator;

pub fn analyze(sector: []u8, entry: *DiskEntry) !void {

    const header = std.mem.bytesToValue(Header, sector);
    if (!std.mem.eql(u8, &header.signature, "EFI PART")) return error.WrongSignature;

    const disk_guid = std.fmt.allocPrintZ(
        allocator, "{}", .{header.guid}) catch root.oom_panic();
    entry.global_identifier = disk_guid.ptr;

    const table_sectors = header.part_length / 4;
    
    var entries_list: std.ArrayList(PartitionEntry) = .init(allocator);

    for (0..table_sectors) |sector_offset| {
        const sector_index = header.part_start + sector_offset;

        try entry.read(sector_index, sector);
        const entries = std.mem.bytesAsSlice(Header_PartitionEntry, sector);

        for (entries) |i| {
            if (i.identifier.isZero()) continue;

            var namebuf: [64]u8 = undefined;
            _ = std.unicode.utf16LeToUtf8(&namebuf, &i.name) catch continue;

            const guidbuf = std.fmt.allocPrintZ(allocator, "{}", .{i.identifier}) catch root.oom_panic();
    
            entries_list.append(.{
                .disk_parent = entry,
                .start_sector = i.first_sector,
                .end_sector = i.last_sector,
                .global_identifier = guidbuf.ptr,
                .readable_name = allocator.dupeZ(u8, &namebuf) catch root.oom_panic(),
            }) catch root.oom_panic();

        }
    }

    const slice = (entries_list.toOwnedSlice() catch root.oom_panic());
    entry.partitions = slice.ptr;
    entry.partitions_length = slice.len;

}

const Header = extern struct {
    signature: [8]u8,
    revision: u32,
    header_size: u32,
    header_crc32: u32,
    _rsvd_0: u32 = 0,
    current: u64,
    backup: u64,
    data_start: u64,
    data_end: u64,
    guid: Guid align(8),
    part_start: u64,
    part_length: u32,
    /// The size of a partition entry, do not cufuse
    /// with part_length!
    part_size: u32,
    part_crc32: u32,
};
const Header_PartitionEntry = extern struct {

    type: Guid,
    identifier: Guid,
    first_sector: u64,
    last_sector: u64,
    attribute: u64,
    name: [36]u16,

};
