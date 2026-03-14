const std = @import("std");
const klib = @import("klib");
const capabilities = klib.capabilities;
const Result = klib.Result;
const Guid = klib.Guid;

pub const std_options = klib.std_oprions;
pub var vtable: klib.KernelVTable = .{ .abi_version = 1 };

pub const Addr = @import("Addr.zig").Addr;
pub const PciDevice = @import("PciDevice.zig");
pub const DeviceList = std.ArrayList(*PciDevice);

const bus_scan = @import("bus_scan.zig");

// Module information
export const @"0ab98143-4f24-4e66-8c82-bed8cac47a21_module-info" linksection(".kernel_modules") = klib.Module{
    .name = "lumiPCI",
    .version = "0.1.0",
    .author = "lumi2021",
    .license = "MPL-2.0",
    .flags = .{ .needs_privilege = true },
    .uuid = klib.Guid.fromString("0ab98143-4f24-4e66-8c82-bed8cac47a21") catch unreachable,
    .init = @ptrCast(&init),
    .deinit = @ptrCast(&deinit),
};
const module_info = @"0ab98143-4f24-4e66-8c82-bed8cac47a21_module-info";

const log = std.log.scoped(.main);
pub var allocator: std.mem.Allocator = undefined;

pub fn init() callconv(.c) bool {
    klib.module_uuid = module_info.uuid;
    log.info("Hello, lumiPCI!", .{});

    allocator = klib.mem.allocator();
    dev_list = .empty;

    log.debug("Registring capabilities...", .{});
    klib.register_cap_call("Devices.PCI", "lspci", &lspci);
    //klib.register_cap_call("Devices.PCI", "device_probe", &lspci);

    // Iterate though all PCI device slots, checks if there is a device
    // and append at the global dev_list list
    log.debug("Iterating devices...", .{});
    list_pci_devices() catch return false;

    return true;
}
pub fn deinit() callconv(.c) void {}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    var buf: [128]u8 = undefined;
    const str = std.fmt.bufPrintZ(&buf, "{s}", .{msg}) catch unreachable;
    klib.kernel_panic(str);
}

var dev_list: DeviceList = undefined;

pub fn list_pci_devices() !void {
    dev_list.clearAndFree(allocator);
    try bus_scan.list_devices(&dev_list);
}

const on_pci_device_probe_bind = @"cap privileged_event_bind [0ab98143-4f24-4e66-8c82-bed8cac47a21]Devices.PCI:device_probe";
fn @"cap privileged_event_bind [0ab98143-4f24-4e66-8c82-bed8cac47a21]Devices.PCI:device_probe"(callback: *const anyopaque, ctx: ?*anyopaque) callconv(.c) bool {
    _ = callback;
    _ = ctx;
    // pci_probe_callbacks.append(allocator, .{
    //     .callback = @ptrCast(@alignCast(callback)),
    //     .context = ctx orelse return false,
    // }) catch @panic("OOM");
    // probe_single(
    //     @ptrCast(@alignCast(callback)),
    //     @ptrCast(@alignCast(ctx)),
    // );
    return true;
}
const on_pci_device_probe_unbind = @"cap privileged_event_unbind [0ab98143-4f24-4e66-8c82-bed8cac47a21]Devices.PCI:device_probe";
fn @"cap privileged_event_unbind [0ab98143-4f24-4e66-8c82-bed8cac47a21]Devices.PCI:device_probe"(callback: *const anyopaque) callconv(.c) void {
    // for (pci_probe_callbacks.items, 0..) |i, idx| {
    //     if (@intFromPtr(i.callback) == @intFromPtr(callback)) {
    //         _ = pci_probe_callbacks.swapRemove(idx);
    //         break;
    //     }
    // }
    _ = callback;
}

const lspci = @"cap privileged_callable [0ab98143-4f24-4e66-8c82-bed8cac47a21]Devices.PCI::lspci";
export fn @"cap privileged_callable [0ab98143-4f24-4e66-8c82-bed8cac47a21]Devices.PCI::lspci"() callconv(.c) void {
    log.warn("lspci", .{});

    for (dev_list.items) |i| {
        log.info("{X:0>2}:{X:0>2}.{X:0>1} [{X:0>2}:{X:0>2}] {s}: [{X:0>4}] {s} - [{X:0>4}] {s}", .{ i.get_bus(), i.get_device(), i.get_function(), i.addr.base_class().read(), i.addr.sub_class().read(), i.type_str, i.addr.vendor_id().read(), i.vendor_str, i.addr.device_id().read(), i.name_str });
    }
}
