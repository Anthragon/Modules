const std = @import("std");
const root = @import("root");
const modules = root.modules;
const sys = root.system;
const debug = root.debug;
const pci = root.devices.pci;

const log = std.log.scoped(.lumiFAT);

const PciDevice = pci.PciDevice;

const allocator = root.mem.heap.kernel_buddy_allocator;

// Module information
pub const module_name: [*:0]const u8 =     "lumiFAT";
pub const module_version: [*:0]const u8 =  "0.1.0";
pub const module_author: [*:0]const u8 =   "lumi2021";
pub const module_liscence: [*:0]const u8 = "MPL-2.0";
pub const module_uuid: u128 = @bitCast(root.utils.Guid.fromString("ed0528e0-fc49-4d8f-bd94-5b19425c41b0") catch unreachable);

pub fn init() callconv(.c) bool {
    log.info("Hello, lumiFAT!", .{});

    return true;
}
pub fn deinit() callconv(.c) void {

}
