const std = @import("std");
const root = @import("root");

const fs = root.fs;
const FsNode = fs.FsNode;

const disk = root.devices.disk;
const DiskInfo = disk.DiskInfo;
const Guid = root.utils.Guid;

const allocator = root.os.heap.kernel_buddy_allocator;

pub fn analyze(sector: []u8, entry: *DiskInfo) !void {

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

            var node = allocator.create(GPTPartitionEntryFileNode) catch unreachable;
            errdefer root.mem.Allocator.destroy(allocator, node);
            node.* = .init(allocator, name, i.identifier, i.first_lba, i.last_lba);
            node.set_context();

            const res = entry.fs_node.append(&node.node);
            if (res.@"error" != .noerror) std.debug.panic("{s}", .{@tagName(res.@"error")});

            std.log.info("added {s}/{s} to fs\n", .{ entry.fs_node.name, node.node.name });

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

pub const GPTPartitionEntryFileNode = struct {

    allocator: std.mem.Allocator,
    node: FsNode,

    guid: Guid,

    first_sector: usize,
    last_sector: usize,

    pub fn init(
        alloc: std.mem.Allocator,
        name: []const u8,
        guid: Guid,
        first_sector: usize,
        last_sector: usize,
    ) @This() {
        var this = @This() {
            .allocator = alloc,
            .node = undefined,
            .guid = guid,
            .first_sector = first_sector,
            .last_sector = last_sector,
        };
        
        const file_name = alloc.dupeZ(u8, name) catch unreachable;

        this.node = .{
            .name = file_name,
            .type = "GPT Disk Partition",
            .type_id = "gpt_disk_part",
            .iterable = false,
            
            .ctx = null,
            .vtable = &vtable,
        };

        return this;
    }
    pub fn deinit(s: @This()) void {
        s.allocator.free(s.node.name);
        s.children.deinit();
    }
    pub fn set_context(s: *@This()) void {
        s.node.ctx = s;
    }

    const vtable: FsNode.FsNodeVtable = .{};

};
