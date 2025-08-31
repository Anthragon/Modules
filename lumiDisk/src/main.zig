const std = @import("std");
const core = @import("root").lib;
const lib = @import("lib");
const capabilities = core.capabilities;

const log = std.log.scoped(.lumiDisk);

const DiskEntry = core.common.DiskEntry;
const PartEntry = core.common.PartEntry;

// Module information
pub const module_name: [*:0]const u8 =     "lumiDisk";
pub const module_version: [*:0]const u8 =  "0.1.0";
pub const module_author: [*:0]const u8 =   "lumi2021";
pub const module_liscence: [*:0]const u8 = "MPL-2.0";
pub const module_uuid: u128 = @bitCast(core.utils.Guid.fromString("eb896ec0-46ef-4996-a8ef-c82c4ac9f05f") catch unreachable);

pub fn init() callconv(.c) bool {
    log.info("Hello, lumiDisk!", .{});

    arena = .init(@import("root").mem.heap.kernel_buddy_allocator);
    allocator = arena.allocator();

    const devices_node = capabilities.get_node_by_guid(core.utils.Guid.fromString("753d870c-e51b-40d2-96b9-beb3bfa8cd02") catch unreachable) orelse return false;
    mass_storage_resource = capabilities.create_resource(core.utils.Guid.fromString("35d36bb8-62f0-43d6-a617-d0bac8069a16") catch unreachable, devices_node, "MassStorage") catch unreachable;

    _ = capabilities.create_callable(mass_storage_resource, "lsblk", @ptrCast(&lsblk)) catch unreachable;
    _ = capabilities.create_callable(mass_storage_resource, "append_device", @ptrCast(&append_device)) catch unreachable;
    
    _ = capabilities.create_callable(mass_storage_resource, "get_disk_by_identifier", @ptrCast(&get_disk_by_identifier)) catch unreachable;
    _ = capabilities.create_callable(mass_storage_resource, "get_disk_by_identifier_part_by_identifier", @ptrCast(&get_disk_by_identifier_part_by_identifier)) catch unreachable;
    
    _ = capabilities.create_callable(mass_storage_resource, "DiskEntry__read", @ptrCast(&DiskEntry.c_read)) catch unreachable;
    _ = capabilities.create_callable(mass_storage_resource, "PartEntry__read", @ptrCast(&PartEntry.c_read)) catch unreachable;

    return true;
}
pub fn deinit() callconv(.c) void {
    arena.deinit();
}

var mass_storage_resource: *capabilities.Node = undefined;

var arena: std.heap.ArenaAllocator = undefined;
var allocator: std.mem.Allocator = undefined;

var disk_list: std.ArrayListUnmanaged(*DiskEntry) = .empty;

fn append_device(
    ctx: *anyopaque,
    devtype: ?[*:0]const u8,
    seclen: usize,
    vtable: *const DiskEntry.VTable,
) callconv(.c) void {

    var entry = allocator.create(DiskEntry) catch @import("root").oom_panic();
    entry.* = .{
        .context = ctx,
        .sectors_length = seclen,
        .vtable = vtable,
        .global_identifier = null,
    };
    if (devtype != null) {
        const copy = allocator.dupeZ(u8, std.mem.sliceTo(devtype.?, 0)) catch @import("root").oom_panic();
        entry.type = copy;
    }

    disk_list.append(allocator, entry) catch @import("root").oom_panic();
    scan_disk(entry);
}

fn get_disk_by_identifier(ident: [*:0]const u8) callconv(.c) ?*DiskEntry {
    const identifier = std.mem.sliceTo(ident, 0);

    for (disk_list.items) |disk| {
        if (disk.global_identifier != null
            and std.mem.eql(u8, std.mem.sliceTo(disk.global_identifier.?, 0), identifier)) return disk;
    }
    return null;
}
fn get_disk_by_identifier_part_by_identifier(disk_ident: [*:0]const u8, part_ident: [*:0]const u8) callconv(.c) ?*PartEntry {
    const disk = get_disk_by_identifier(disk_ident) orelse return null;
    const parts = disk.partitions[0..disk.partitions_length];

    const identifier = std.mem.sliceTo(part_ident, 0);

    for (parts, 0..) |part, i| {
        if (part.global_identifier != null
        and std.mem.eql(u8, std.mem.sliceTo(part.global_identifier.?, 0), identifier))
            return &disk.partitions[i];
    }
    return null;
}

fn scan_disk(disk_entry: *DiskEntry) void {

    var buf: [512]u8 = undefined;
    disk_entry.read(0, &buf) catch @panic("Failed to read disk");
    
    const partitions = std.mem.bytesAsSlice(MBRPartition, buf[0x1be .. 0x1fe]);

    var isgpt = false;
    for (partitions) |i| {
        if (i.status == .inactive and i.type == 0xee) {
            isgpt = true;
            break;
        }
    }

    if (isgpt) {
        disk_entry.read(1, &buf) catch @panic("Failed to read disk");
        @import("gpt.zig").analyze(&buf, disk_entry) catch @panic("Failed to read disk");
    } else {
        @import("mbr.zig").analyze(&buf, disk_entry) catch @panic("Failed to read disk");
    }

}


fn lsblk() callconv(.c) void {

    for (disk_list.items) |i| {
        const ds = core.utils.units.calc(i.sectors_length*512, &core.utils.units.data);
        log.info("{s: <15} Disk    {d: >5.2} {s: <6} {s}", .{ i.type, ds.@"0", ds.@"1", i.global_identifier orelse "--" });

        for (0..i.partitions_length) |j| {
            const p = i.partitions[j];
            const ps = core.utils.units.calc((p.end_sector - p.start_sector)*512, &core.utils.units.data);
            log.info("   {s: <12} Part    {d: >5.2} {s: <6} {s}", .{ p.readable_name, ps.@"0", ps.@"1", p.global_identifier orelse "--" });
        }
    }

}

const MBRPartition = packed struct {
    status: Status,
    start_chs: u24,
    type: u8,
    end_chs: u24,
    abs_start_chs: u32,
    sector_len: u32,

    const Status = enum(u8) {
        inactive = 0x00,
        bootable = 0x80,
        _,
    };
};

