const std = @import("std");
const root = @import("root");

const disk = root.devices.disk;
const DiskEntry = disk.DiskEntry;
const Guid = root.utils.Guid;

const allocator = root.os.heap.kernel_buddy_allocator;
const PartitionEntryFileNode = root.fs.default_nodes.PartitionEntry;

pub fn analyze(sector: []u8, entry: *DiskEntry) !void {

    const header = std.mem.bytesToValue(Header, sector);
    if (!std.mem.eql(u8, &header.signature, "EFI PART")) return error.WrongSignature;

    const table_sectors = header.part_length / 4;
    
    for (0..table_sectors) |sector_offset| {
        const sector_index = header.part_start + sector_offset;

        try entry.read(sector_index, sector);
        const entries = std.mem.bytesAsSlice(PartitionEntry, sector);

        for (entries) |i| {
            if (i.identifier.isZero()) continue;

            var namebuf: [64]u8 = undefined;
            _ = std.unicode.utf16LeToUtf8(&namebuf, &i.name) catch continue;
            const name = std.mem.sliceTo(&namebuf, 0); 

            var node = allocator.create(PartitionEntryFileNode) catch unreachable;
            errdefer root.mem.Allocator.destroy(allocator, node);
            node.* = PartitionEntryFileNode.init(
                allocator,
                name,
                i.first_lba,
                i.last_lba,
            );
            node.set_context();

            const res = entry.fs_node.node.append(&node.node);
            if (res.@"error" != .noerror) std.debug.panic("{s}", .{@tagName(res.@"error")});

            std.log.info("added {s}/{s} to fs\n", .{ entry.fs_node.node.name, node.node.name });

        }
    }

    std.log.info("\n", .{});
    root.fs.lsroot();
    std.log.info("\n", .{});

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
const PartitionEntry = extern struct {
    type: Guid,
    identifier: Guid,
    first_lba: u64,
    last_lba: u64,
    attribute: u64,
    name: [36]u16
};
