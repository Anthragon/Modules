const std = @import("std");
const root = @import("main.zig");
const core = @import("root").lib;

pub const FatContex = struct {
    bytes_per_sector: usize,
    sectors_per_cluster: usize,

    fat_start: usize,
    fat_length: usize,
    fat_count: usize,
    
    root_dir: usize,
    root_len: usize,

    data_start: usize,
    total_clusters: usize,
    
    type: FatSubType,
};
pub const FatSubType = enum { FAT12, FAT16, FAT32 };

const log = std.log.scoped(.fatfs);

fn get_next_cluster(
    ctx: FatContex,
    current_cluster: usize,
    disk: *core.common.DiskEntry,
) ?usize {
    var buf: [512]u8 = undefined;

    const fat_t = ctx.type;
    const fat_start = ctx.fat_start;

    if (fat_t == .FAT12) {
        const iseven = current_cluster % 2 == 0;
        const fat_index = (current_cluster * 3) / 2;
        const sector_off = fat_index / 512;
        const rel_index = fat_index % 512;

        
        disk.read(fat_start + sector_off, &buf) catch unreachable;

        log.debug("Seeking cluster {} of sector {} ({} in sector {} of fat table)...",
            .{fat_index, current_cluster, rel_index, sector_off});

        const raw_cluster = std.mem.readInt(u16, buf[rel_index..][0..2], .little);
        const cluster = if (iseven) (raw_cluster & 0x0fff) else (raw_cluster >> 4);

        log.debug("found cluster {} (0x{X:0>3})", .{cluster, cluster});

        return if (cluster >= 0x002 and cluster <= 0xfef) (cluster - 2) else null;
    }
    else if (fat_t == .FAT16) {
        const fat_index = current_cluster * 2;
        const sector_off = fat_index / 512;
        const rel_index = fat_index % 512;
        disk.read(fat_start + sector_off, &buf) catch unreachable;

        const cluster = std.mem.readInt(u16, buf[rel_index..][0..2], .little);
        return if (cluster >= 0x0002 and cluster <= 0xffef) (cluster - 2) else null;
    }
    else {
        const fat_index = current_cluster * 4;
        const sector_off = fat_index / 512;
        const rel_index = fat_index % 512;
        disk.read(fat_start + sector_off, &buf) catch unreachable;

        const cluster = std.mem.readInt(u32, buf[rel_index..][0..4], .little);
        return if (cluster >= 0x0000_0002 and cluster <= 0xffff_ffef) (cluster - 2) else null;
    }
}
