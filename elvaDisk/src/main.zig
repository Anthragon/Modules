const std = @import("std");
const root = @import("root");
const modules = root.modules;
const sys = root.system;
const debug = root.debug;
const pci = root.devices.pci;

const PciDevice = pci.PciDevice;

const allocator = root.mem.heap.kernel_buddy_allocator;

// Module information
pub const module_name: [*:0]const u8 =     "elvaDisk";
pub const module_version: [*:0]const u8 =  "0.1.0";
pub const module_author: [*:0]const u8 =   "System Elva Team";
pub const module_liscence: [*:0]const u8 = "MPL-2.0";
pub const module_uuid: u128 = @bitCast(root.utils.Guid.fromString("eb896ec0-46ef-4996-a8ef-c82c4ac9f05f") catch unreachable);

pub fn init() callconv(.c) bool {
    std.log.info("Hello, elvaDisk!\n", .{});

    std.log.debug("Trying to bind to the event...\n", .{});
    root.modules.temp_bind_event("device_disk_probe", probe_disk, null) catch {
        std.log.warn("Error while binding!\n", .{});
        return false;
    };
    std.log.debug("Bind ended sucessfully!", .{});

    return true;
}
pub fn deinit() callconv(.c) void {

}


pub fn probe_disk(de: ?*anyopaque) usize {
    var disk_entry: *root.devices.disk.DiskEntry = @ptrCast(@alignCast(de));

    var buf: [512]u8 = undefined;
    disk_entry.read(0, &buf) catch return 1;
    
    const partitions = std.mem.bytesAsSlice(MBRPartition, buf[0x1be .. 0x1fe]);

    var isgpt = false;
    for (partitions) |i| {
        if (i.status == .inactive and i.type == 0xee) {
            isgpt = true;
            break;
        }
    }

    if (isgpt) {
        disk_entry.read(1, &buf) catch return 1;
        @import("gpt.zig").analyze(&buf, disk_entry) catch return 1;
    } else {
        @import("mbr.zig").analyze(&buf, disk_entry) catch return 1;
    }

    return 0;
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


