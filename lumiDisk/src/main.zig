const std = @import("std");
const klib = @import("klib");

pub const std_options = klib.std_oprions;

// Module information
const module_info = @"eb896ec0-46ef-4996-a8ef-c82c4ac9f05f_module-info";
export const @"eb896ec0-46ef-4996-a8ef-c82c4ac9f05f_module-info" linksection(".kernel_modules") = klib.Module{
    .name = "lumiDisk",
    .version = "0.1.0",
    .author = "lumi2021",
    .license = "MPL-2.0",
    .flags = .{ .needs_privilege = true },
    .uuid = klib.Guid.fromString("eb896ec0-46ef-4996-a8ef-c82c4ac9f05f") catch unreachable,
    .init = @ptrCast(&init),
    .deinit = @ptrCast(&deinit),
};

const log = std.log.scoped(.lumiDisk);

const DiskEntry = klib.common.DiskEntry;
const PartEntry = klib.common.PartEntry;

pub fn init() callconv(.c) bool {
    klib.module_uuid = module_info.uuid;
    log.info("Hello, lumiDisk!", .{});

    allocator = klib.mem.allocator();

    log.debug("Registring capabilities...", .{});
    klib.register_cap_call("Devices.MassStorage", "list", &lsblk);
    klib.register_cap_call("Devices.MassStorage", "get_disk_by_id", &get_disk_by_id);
    klib.register_cap_call("Devices.MassStorage", "get_part_by_id", &get_part_by_id);

    return true;
}
pub fn deinit() callconv(.c) void {}

var register_device: *const fn (devname: [*:0]const u8, identifier: u128, subclass: usize, canSee: usize, canRead: usize, canControl: usize) callconv(.c) void = undefined;
var remove_device: *const fn (dev: usize) callconv(.c) void = undefined;

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

const get_disk_by_id = @"cap privileged_callable [0eb896ec0-46ef-4996-a8ef-c82c4ac9f05f_module-info]Devices.MassStorage::get_disk_by_id";
export fn @"cap privileged_callable [0eb896ec0-46ef-4996-a8ef-c82c4ac9f05f_module-info]Devices.MassStorage::get_disk_by_id"(ident: [*:0]const u8) callconv(.c) ?*DiskEntry {
    const identifier = std.mem.sliceTo(ident, 0);

    for (disk_list.items) |disk| {
        if (disk.global_identifier != null and std.mem.eql(u8, std.mem.sliceTo(disk.global_identifier.?, 0), identifier)) return disk;
    }
    return null;
}

const get_part_by_id = @"cap privileged_callable [0eb896ec0-46ef-4996-a8ef-c82c4ac9f05f_module-info]Devices.MassStorage::get_part_by_id";
fn @"cap privileged_callable [0eb896ec0-46ef-4996-a8ef-c82c4ac9f05f_module-info]Devices.MassStorage::get_part_by_id"(disk_ident: [*:0]const u8, part_ident: [*:0]const u8) callconv(.c) ?*PartEntry {
    const disk = get_disk_by_id(disk_ident) orelse return null;
    const parts = disk.partitions[0..disk.partitions_length];

    const identifier = std.mem.sliceTo(part_ident, 0);

    for (parts, 0..) |part, i| {
        if (part.global_identifier != null and std.mem.eql(u8, std.mem.sliceTo(part.global_identifier.?, 0), identifier))
            return &disk.partitions[i];
    }
    return null;
}

fn scan_disk(disk_entry: *DiskEntry) void {
    var buf: [512]u8 = undefined;
    disk_entry.read(0, &buf) catch @panic("Failed to read disk");

    const partitions = std.mem.bytesAsSlice(MBRPartition, buf[0x1be..0x1fe]);

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

const lsblk = @"cap privileged_callable [0eb896ec0-46ef-4996-a8ef-c82c4ac9f05f_module-info]Devices.MassStorage::lsblk";
export fn @"cap privileged_callable [0eb896ec0-46ef-4996-a8ef-c82c4ac9f05f_module-info]Devices.MassStorage::lsblk"() callconv(.c) void {
    log.warn("lsblk", .{});

    for (disk_list.items) |i| {
        const ds = klib.units.calc(i.sectors_length * 512, &klib.units.data);
        log.info("{s: <15} Disk    {d: >5.2} {s: <6} {s}", .{ i.type, ds.@"0", ds.@"1", i.global_identifier orelse "--" });

        for (0..i.partitions_length) |j| {
            const p = i.partitions[j];
            const ps = klib.units.calc((p.end_sector - p.start_sector) * 512, &klib.units.data);
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
