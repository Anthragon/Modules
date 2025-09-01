const std = @import("std");
const root = @import("main.zig");
const core = @import("root").lib;

pub const FatContext = struct {
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

const DirEntry = extern struct {
    name: [8]u8,
    extension: [3]u8,
    file_attributes: DirEntryFileAttributes,
    user_attributes: u8,
    creation_time_tenths: u8,
    creation_time: u16,
    creation_date: u16,
    last_access_date: u16,
    first_cluster_high: u16,
    last_modified_time: u16,
    last_modified_date: u16,
    first_cluster_low: u16,
    file_size: u32,

    pub fn is_null(self: *const DirEntry) bool {
        return self.name[0] == 0x00;
    }
    pub fn is_free(self: *const DirEntry) bool {
        return self.name[0] == 0x00 or self.name[0] == 0xE5;
    }

    pub inline fn is_directory(self: *const DirEntry) bool {
        return self.file_attributes.directory;
    }

    pub inline fn is_lfn_entry(self: *const DirEntry) bool {
        return @as(u8, @bitCast(self.file_attributes)) == 0x0F;
    }

    pub fn get_name(self: *const DirEntry) []const u8 {
        return std.mem.trim(u8, &self.name, &[_]u8{' '});
    }

    pub fn get_extension(self: *const DirEntry) []const u8 {
        return std.mem.trim(u8, &self.extension, &[_]u8{' '});
    }

    pub fn get_cluster(self: *const DirEntry) ?u32 {
        const val = @as(u32, @intCast(self.first_cluster_high)) << 16 | self.first_cluster_low;
        return if (val < 2) null else val;
    }
};
const DirEntryFileAttributes = packed struct(u8) {
    read_only: bool,
    hidden: bool,
    system: bool,
    volume_label: bool,
    directory: bool,
    dirty: bool,
    _reserved_0: u2,
};

const log = std.log.scoped(.fatfs);

fn get_next_cluster(
    ctx: *const FatContext,
    current_cluster: usize,
    part: *const core.common.PartEntry,
) ?usize {
    var buf: [512]u8 = undefined;

    const fat_t = ctx.type;
    const fat_start = ctx.fat_start;

    if (fat_t == .FAT12) {
        const iseven = current_cluster % 2 == 0;
        const fat_index = (current_cluster * 3) / 2;
        const sector_off = fat_index / 512;
        const rel_index = fat_index % 512;

        part.read(fat_start + sector_off, &buf) catch unreachable;

        log.debug("Seeking cluster {} of sector {} ({} in sector {} of fat table)...",
            .{fat_index, current_cluster, rel_index, sector_off});

        const raw_cluster = std.mem.readInt(u16, buf[rel_index..][0..2], .little);
        const cluster = if (iseven) (raw_cluster & 0x0fff) else (raw_cluster >> 4);

        log.debug("found cluster {} (0x{X:0>3})", .{cluster, cluster});

        return if (cluster >= 0x002 and cluster <= 0xfef) cluster else null;
    }
    else if (fat_t == .FAT16) {
        const fat_index = current_cluster * 2;
        const sector_off = fat_index / 512;
        const rel_index = fat_index % 512;
        part.read(fat_start + sector_off, &buf) catch unreachable;

        const cluster = std.mem.readInt(u16, buf[rel_index..][0..2], .little);
        return if (cluster >= 0x0002 and cluster <= 0xffef) cluster else null;
    }
    else {
        const fat_index = current_cluster * 4;
        const sector_off = fat_index / 512;
        const rel_index = fat_index % 512;
        part.read(fat_start + sector_off, &buf) catch unreachable;

        const cluster = std.mem.readInt(u32, buf[rel_index..][0..4], .little);
        return if (cluster >= 0x0000_0002 and cluster <= 0xffff_ffef) cluster else null;
    }
}

pub inline fn sector_from_cluster(ctx: *const FatContext, cluster: usize) usize {
    return ctx.data_start + cluster - 2;
}
pub inline fn cluster_from_sector(ctx: *const FatContext, sector: usize) usize {
    return sector - ctx.data_start + 2;
}

pub fn get_root_directory_entries(allocator: std.mem.Allocator, part: *const core.common.PartEntry) []DirEntry {
    const ctx: *FatContext = @ptrCast(@alignCast(part.fs_context));

    if (ctx.type != .FAT32) {
        const root_start = ctx.root_dir;
        const root_len = ctx.root_len;

        var buffer = allocator.alignedAlloc(u8, @alignOf(DirEntry), 512) catch oom_panic();
        var index: usize = 0;

        const entries = b: {
            while (index < root_len) : (index += 1) {

                const nbs = (index+1) * 512;
                if (allocator.resize(buffer, nbs)) buffer.len = nbs
                else buffer = allocator.realloc(buffer, nbs) catch oom_panic();

                const buf: []u8 = buffer[index*512..][0..512];
                part.read(root_start + index, buf) catch unreachable;

                const entries = std.mem.bytesAsSlice(DirEntry, buf);
                for (entries, 0..) |v, i| if (v.is_null()) break :b index*16 + i;

            }
            break :b root_len*16;
        };

        buffer = allocator.realloc(buffer, entries * 32) catch oom_panic();
        return @alignCast(std.mem.bytesAsSlice(DirEntry, buffer));

    }
    else @panic("TODO Fat32 get_root_directory_entries");
}

pub fn get_directory_entries(allocator: std.mem.Allocator, cluster: usize, part: *const core.common.PartEntry) []DirEntry {
    const ctx: *FatContext = @ptrCast(@alignCast(part.fs_context));

    var buffer = allocator.alignedAlloc(u8, @alignOf(DirEntry), 512) catch oom_panic();
    var index: usize = 0;
    var currcluster: ?usize = cluster;

    const entries = b: {
        while (currcluster != null) : ({
            currcluster = get_next_cluster(ctx, currcluster.?, part);
            index += 1;
        }) {
            const sector = sector_from_cluster(ctx, currcluster.?);

            const nbs = (index+1) * 512;
            if (allocator.resize(buffer, nbs)) buffer.len = nbs
            else buffer = allocator.realloc(buffer, nbs) catch oom_panic();

            const buf: []u8 = buffer[index*512..][0..512];
            part.read(sector, buf) catch unreachable;

            const entries = std.mem.bytesAsSlice(DirEntry, buf);
            for (entries, 0..) |v, i| if (v.is_null()) break :b index*16 + i;

        }
        break :b index*16;
    };

    buffer = allocator.realloc(buffer, entries * 32) catch oom_panic();
    return @alignCast(std.mem.bytesAsSlice(DirEntry, buffer));

}

pub fn read_file(cluster: usize, buffer: []u8, part: *const core.common.PartEntry) usize {
    const ctx: *FatContext = @ptrCast(@alignCast(part.fs_context));

    var index: usize = 0;
    var cur_cluster: ?usize = cluster;
    while (cur_cluster != null and (index+1)*512 < buffer.len) : ({
        index += 1;
        cur_cluster = get_next_cluster(ctx, cur_cluster.?, part);
    }) {
        const sector = sector_from_cluster(ctx, cur_cluster.?);
        const bufslice = buffer[index*512 .. (index+1)*512];
        part.read(sector, bufslice) catch return index*512;
    }

    // Check if EOC
    if (cur_cluster == null) return index*512;

    if (index*512 < buffer.len) {
        var temp_buf: [512]u8 = undefined;
        const sector = sector_from_cluster(ctx, cur_cluster.?);
        part.read(sector, &temp_buf) catch return index*512;
        const restslice = buffer[index * 512 ..];
        @memcpy(restslice, temp_buf[0..restslice.len]);
    }

    return buffer.len;
}


fn oom_panic() noreturn { @import("root").oom_panic(); }