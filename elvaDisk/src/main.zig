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
    debug.print("Hello, elvaDisk!\n", .{});

    return true;
}
pub fn deinit() callconv(.c) void {

}
