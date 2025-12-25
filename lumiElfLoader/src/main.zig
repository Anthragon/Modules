const std = @import("std");
const root = @import("root");
const pci = @import("pci_lib");
const disk = @import("disk_lib");
const elf = std.elf;
const modules = root.modules;
const capabilities = root.capabilities;

const log = std.log.scoped(.lumiAHCI);

const PciDevice = pci.PciDevice;
const PciDeviceQuery = pci.PciDeviceQuery;

var arena: std.heap.ArenaAllocator = undefined;
var allocator: std.mem.Allocator = undefined;

// Module information
pub const module_name: [*:0]const u8 = "lumiElfLoader";
pub const module_version: [*:0]const u8 = "0.1.0";
pub const module_author: [*:0]const u8 = "lumi2021";
pub const module_liscence: [*:0]const u8 = "MPL-2.0";
pub const module_uuid: u128 = @bitCast(root.utils.Guid.fromString("be423801-ec1f-4702-93c3-e692a6277bc3") catch unreachable);

pub fn init() callconv(.c) bool {
    log.info("Hello, lumiElfLoader!", .{});

    arena = .init(root.mem.heap.kernel_buddy_allocator);
    allocator = arena.allocator();

    return true;
}
pub fn deinit() callconv(.c) void {}


