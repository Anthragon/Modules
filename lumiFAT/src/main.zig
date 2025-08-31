const std = @import("std");
pub const core = @import("root").lib;
const capabilities = core.capabilities;
const fat = @import("fat.zig");

const log = std.log.scoped(.lumiFAT);

var arena: std.heap.ArenaAllocator = undefined;
var allocator: std.mem.Allocator = undefined;

// Module information
pub const module_name: [*:0]const u8 = "lumiFAT";
pub const module_version: [*:0]const u8 = "0.1.0";
pub const module_author: [*:0]const u8 = "lumi2021";
pub const module_liscence: [*:0]const u8 = "MPL-2.0";
pub const module_uuid: u128 = @bitCast(core.utils.Guid.fromString("ed0528e0-fc49-4d8f-bd94-5b19425c41b0") catch unreachable);

const FileSystemEntry = core.common.FileSystemEntry;
const PartEntry = core.common.PartEntry;

const FatRootNode = @import("FsNodes/FatRoot.zig");

pub var fs: struct {
    chroot: core.callables.fs.chroot,
    append_file_system: core.callables.fs.append_file_system,
    remove_file_system: core.callables.fs.remove_file_system,
} = undefined;
pub var mass_storage: struct {
    DiskEntry__read: core.callables.device.mass_storage.DiskEntry__read,
    PartEntry__read: core.callables.device.mass_storage.PartEntry__read,
} = undefined;

pub fn init() callconv(.c) bool {
    log.info("Hello, lumiFAT!", .{});

    arena = .init(@import("root").mem.heap.kernel_buddy_allocator);
    allocator = arena.allocator();

    fs.chroot = @ptrCast((capabilities.get_node("Fs.chroot") orelse return false).data.callable);
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

var mountedList: std.ArrayListUnmanaged(*FatRootNode) = .empty;

fn scan_partition(part: *PartEntry) callconv(.c) bool {
    
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
fn mount_partition(part: *PartEntry) callconv(.c) *core.common.FsNode {
    
    var buf: [512]u8 = undefined;
    _ = mass_storage.PartEntry__read(part, 0, &buf, 512);
    const bpb = std.mem.bytesToValue(BootSector, &buf);

    log.debug("{}", .{bpb});

    const bytes_per_sector:usize = @intCast(bpb.bytes_per_sector);
    const total_sectors: usize = bpb.total_sectors();
    const fat_sectors: usize = bpb.table_size();
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

    const ftype: FatType = b: {
        if (clusters < 4085) break :b .FAT12;
        if (clusters < 65525) break :b .FAT16;
        break :b .FAT32;
    };

    const ctx = allocator.create(FatContext) catch @import("root").oom_panic();
    ctx.* = .{
        .bytes_per_sector = bytes_per_sector,
        .sectors_per_cluster = bpb.sectors_per_cluster,
        .fat_start = fat_start,
        .fat_length = fat_length,
        .fat_count = num_fats,
        .root_dir = root_dir_table_start,
        .root_len = root_dir_table_len,

        .data_start = data_start,
        .total_clusters = clusters,

        .type = ftype
    };
    part.fs_context = ctx;

    const volume_label = std.mem.sliceTo(part.readable_name, 0);
    const fat_root = FatRootNode.init(allocator, volume_label, part);
    mountedList.append(allocator, fat_root) catch @import("root").oom_panic();

    fat_root.load_children(allocator);

    return &fat_root.node;
}

const BootSector = packed struct {
    jump: u24,
    _oem_name: u64,

    // bios parameter block after here
    bytes_per_sector: u16,
    sectors_per_cluster: u8,
    reserved_sector_count: u16,
    fat_table_count: u8,
    root_entry_count: u16,         //0x11
    total_sectors_16: u16,         //0x13
    media_descriptor: u8,          //0x15
    table_size_16: u16,            //0x16
    // DOS 3.31 (0x18+)
    sectors_per_track: u16,
    head_side_count: u16,
    hidden_sector_count: u32,
    total_sectors_32: u32,

    // Extended BPB (0x26+)
    extended: packed union {
        fat12_16: packed struct {
            phys_drive_num: u8,
            _rsvd_0: u8,
            extended_signature: u8,
            serial_number: u32,
            _volume_label: u88,
            _fs_type_string: u64,
        },
        fat32: packed struct {
            table_size_32: u32,
            flags: u16,
            version: u16,
            root_directory: u32,
            // too lazy to continue
        }
    },
    

    // FAT32 Extended (0x)

    pub fn oem_name(s: *const @This()) []const u8 {
        return std.mem.trimRight(u8, std.mem.asBytes(&s._oem_name), &.{0x20});
    }

    pub fn total_sectors(s: *const @This()) usize {
        return if (s.total_sectors_16 == 0) s.total_sectors_32
        else s.total_sectors_16;
    }
    pub fn table_size(s: *const @This()) usize {
        return if (s.table_size_16 == 0) s.extended.fat32.table_size_32
        else s.table_size_16;
    }

    pub fn format(s: *const @This(), comptime _: []const u8, _: std.fmt.FormatOptions, fmt: anytype) !void {

        const jmp = std.mem.asBytes(&s.jump);

        try fmt.print("0x{x:0>4} - ", .{ @offsetOf(BootSector, "jump") });
        try fmt.print("Jump:                          {x:0>2} {x:0>2} {x:0>2}\n", .{ jmp[0], jmp[1], jmp[2] });

        try fmt.print("0x{x:0>4} - ", .{ @offsetOf(BootSector, "_oem_name") });
        try fmt.print("OEM Name:                      {s}\n", .{ s.oem_name() });

        try fmt_field_w_address(fmt, s, "Bytes/Sector:", "bytes_per_sector", "{}");
        try fmt_field_w_address(fmt, s, "Sectors/Cluster:", "sectors_per_cluster", "{}");
        try fmt_field_w_address(fmt, s, "Reserved Count:", "reserved_sector_count", "{}");
        try fmt_field_w_address(fmt, s, "FAT Tables Count:", "fat_table_count", "{}");
        try fmt_field_w_address(fmt, s, "Root Entries:", "root_entry_count", "{}");
        try fmt_field_w_address(fmt, s, "Total Secotrs (16):", "total_sectors_16", "{}");
        try fmt_field_w_address(fmt, s, "Media Descriptor:", "media_descriptor", "{X:0>2}");
        try fmt_field_w_address(fmt, s, "Table Size (16):", "table_size_16", "{}");
        try fmt_field_w_address(fmt, s, "Sectors/Track:", "sectors_per_track", "{}");
        try fmt_field_w_address(fmt, s, "Heads:", "head_side_count", "{}");
        try fmt_field_w_address(fmt, s, "Hidden Count:", "hidden_sector_count", "{}");
        try fmt_field_w_address(fmt, s, "Total Sectors (32):", "total_sectors_32", "{}");
    }

    fn fmt_field_w_address(
        fmt: anytype,
        bpb: *const @This(),
        comptime display_name: []const u8,
        comptime field_name: []const u8,
        comptime value_fmt: []const u8,
    ) !void {
        try fmt.print("0x{x:0>4} - ", .{ @offsetOf(BootSector, field_name) });
        try fmt.writeAll(std.fmt.comptimePrint("{s: <30} ", .{display_name}));
        try fmt.print(value_fmt, .{ @field(bpb, field_name) });
        try fmt.writeByte('\n');
    }
    fn fmt_field_n_address(
        fmt: anytype,
        comptime display_name: []const u8,
        comptime value_fmt: []const u8,
        value: anytype,
    ) !void {
        try fmt.writeAll("0x---- - ");
        try fmt.writeAll(std.fmt.comptimePrint("{s: <30} ", .{display_name}));
        try fmt.print(value_fmt, value);
        try fmt.writeByte('\n');
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
    pub fn is_null(self: *const DirEntry) bool {
        return self.name[0] == 0x00;
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
    fat_type: FatType,

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


const FatContext = fat.FatContext;
const FatType = fat.FatSubType;
