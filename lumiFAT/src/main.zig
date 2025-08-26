const std = @import("std");
const core = @import("root").lib;
const capabilities = core.capabilities;

const log = std.log.scoped(.lumiFAT);

var arena: std.heap.ArenaAllocator = undefined;
var allocator: std.mem.Allocator = undefined;

// Module information
pub const module_name: [*:0]const u8 = "lumiFAT";
pub const module_version: [*:0]const u8 = "0.1.0";
pub const module_author: [*:0]const u8 = "lumi2021";
pub const module_liscence: [*:0]const u8 = "MPL-2.0";
pub const module_uuid: u128 = @bitCast(core.utils.Guid.fromString("ed0528e0-fc49-4d8f-bd94-5b19425c41b0") catch unreachable);

const FileSystemEntry = core.FileSystemEntry;

var fs: struct {
    append_file_system: core.callables.fs.append_file_system,
    remove_file_system: core.callables.fs.remove_file_system,
} = undefined;
var mass_storage: struct {
    DiskEntry__read: core.callables.device.mass_storage.DiskEntry__read,
    PartEntry__read: core.callables.device.mass_storage.PartEntry__read,
} = undefined;

pub fn init() callconv(.c) bool {
    log.info("Hello, lumiFAT!", .{});

    arena = .init(@import("root").mem.heap.kernel_buddy_allocator);
    allocator = arena.allocator();

    fs.append_file_system = @ptrCast((capabilities.get_node("Fs.append_file_system") orelse return false).data.callable);
    fs.remove_file_system = @ptrCast((capabilities.get_node("Fs.remove_file_system") orelse return false).data.callable);

    mass_storage.DiskEntry__read = @ptrCast((capabilities.get_node("Devices.MassStorage.DiskEntry__read") orelse return false).data.callable);
    mass_storage.PartEntry__read = @ptrCast((capabilities.get_node("Devices.MassStorage.PartEntry__read") orelse return false).data.callable);

    _ = fs.append_file_system(.{
        .name = "FAT",
        .vtable = &fsvtable,
    });

    return true;
}
pub fn deinit() callconv(.c) void {}

const fsvtable: FileSystemEntry.VTable = .{
    .scan = scan_partition,
    .mount = mount_partition,
};

fn scan_partition(part: *anyopaque) callconv(.c) bool {
    
    var buf: [512]u8 = undefined;
    _ = mass_storage.PartEntry__read(part, 0, &buf, 512);

    if (buf[510] != 0x55 or buf[511] != 0xAA) return false;

    // all options for the first 3 bytes:
    //  EB ?? 90
    //  E9 ?? ??
    //  69 ?? ??
    //  90 EB ??

    if (buf[0] == 0xEB and buf[2] == 0x90) {}
    else if (buf[0] == 0x90 and buf[1] == 0xEB) {}
    else if (buf[0] == 0xE9 or buf[0] == 0x69) {}
    else return false;

    return true;
}
fn mount_partition(part: *anyopaque) callconv(.c) void {
    
    var buf: [512]u8 = undefined;
    _ = mass_storage.PartEntry__read(part, 0, &buf, 512);
    const bpb = std.mem.bytesAsValue(BootSector, &buf);

    const bytes_per_sector:usize = @intCast(bpb.bytes_per_sector);
    const total_sectors: usize = if (bpb.total_sectors_16 != 0) @intCast(bpb.total_sectors_16) else @intCast(bpb.total_sectors_32);
    const fat_sectors: usize = @intCast(bpb.table_size_16);
    const num_fats: usize = @intCast(bpb.fat_table_count);
    const reserved_sectors: usize = @intCast(bpb.reserved_sector_count);
    const root_entry_count: usize = @intCast(bpb.root_entry_count);

    const fat_start = reserved_sectors;
    const fat_length = (fat_sectors * num_fats);
    const root_dir_table_start = fat_start + fat_length;
    const root_dir_table_len = std.math.divCeil(usize,
        root_entry_count * @sizeOf(DirEntry),
        bytes_per_sector) catch unreachable;
    
    const data_start = root_dir_table_start + root_dir_table_len;
    const data_len: usize = total_sectors - data_start;

    const clusters = data_len / @as(usize, @intCast(bpb.sectors_per_cluster));

    const ftype: FATType = b: {
        if (clusters < 4085) break :b .FAT12;
        if (clusters < 65525) break :b .FAT16;
        break :b .FAT32;
    };

    log.info("{s}", .{@tagName(ftype)});

}

const BootSector = packed struct {
    jump: u24, // 3
    oem_name: u64, // 11
    bytes_per_sector: u16,
    sectors_per_cluster: u8,
    reserved_sector_count: u16,
    fat_table_count: u8,
    root_entry_count: u16,
    total_sectors_16: u16,
    media_descriptor: u8,
    table_size_16: u16,
    sectors_per_track: u16,
    head_side_count: u16,
    hidden_sector_count: u32,
    total_sectors_32: u32,

    pub fn total_sectors(s: *@This()) usize {
        return if (s.total_sectors_16 == 0) s.total_sectors_32
        else s.total_sectors_16;
    }
};

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

pub const FileSystem_FAT_Data = struct {
    fat_type: FATType,

    fat_table_ptr: usize,
    fat_table_len: usize,

    root_dir_ptr: usize,
    root_dir_len: usize,

    data_start_ptr: usize
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

const FATType = enum { FAT12, FAT16, FAT32 };
