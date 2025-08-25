const std = @import("std");
const root = @import("root");
const lib = @import("lib");
const modules = root.modules;
const sys = root.system;
const capabilities = root.capabilities;
const Guid = root.utils.Guid;

pub const internal = switch (sys.arch) {
    //.x86 => ,
    .x86_64 => @import("x86_64/pci.zig"),
    //.aarch64 => ,
    else => unreachable,
};

const PciDeviceProbeEntry = struct {
    context: *anyopaque,
    callback: lib.callables.DeviceProbeCallback,
};

pub const PciDevice = lib.PciDevice;
pub const PciDeviceQuery = lib.PciDeviceQuery;

const Addr = internal.Addr;
pub const DeviceList = std.ArrayList(*PciDevice);
const DeviceProbeCallback = lib.callables.DeviceProbeCallback;

// Module information
pub const module_name: [*:0]const u8 = "lumiPCI";
pub const module_version: [*:0]const u8 = "0.1.0";
pub const module_author: [*:0]const u8 = "lumi2021";
pub const module_liscence: [*:0]const u8 = "MPL-2.0";
pub const module_uuid: u128 = @bitCast(root.utils.Guid.fromString("0ab98143-4f24-4e66-8c82-bed8cac47a21") catch unreachable);

const log = std.log.scoped(.lumiPCI);

var arena: std.heap.ArenaAllocator = undefined;
var allocator: std.mem.Allocator = undefined;

pub fn init() callconv(.c) bool {
    log.info("Hello, lumiPCI!", .{});

    // Creating an specific arena allocator for this module
    arena = .init(root.mem.heap.kernel_buddy_allocator);
    allocator = arena.allocator();

    // Initializing device list with scoped allocator
    dev_list = .init(allocator);

    // Creating the resource interfaces
    const devices_node = capabilities.get_node_by_guid(Guid.fromString("753d870c-e51b-40d2-96b9-beb3bfa8cd02") catch unreachable);
    pci_resource = capabilities.create_resource(Guid.fromString("4a56f4da-feee-4715-aed3-25f754025840") catch unreachable, devices_node, "PCI") catch @panic("Not Implemented");

    _ = capabilities.create_callable(pci_resource, "lspci", @ptrCast(&lspci)) catch unreachable;
    _ = capabilities.create_event(pci_resource, "device_probe", on_pci_device_probe_bind, on_pci_device_probe_unbind) catch unreachable;

    // Iterate though all PCI device slots, checks if there is a device
    // and append at the global dev_list list
    list_pci_devices() catch return false;

    return true;
}
pub fn deinit() callconv(.c) void {
    arena.deinit();
}

var pci_resource: *capabilities.Node = undefined;
var pci_probe_callbacks: std.ArrayListUnmanaged(PciDeviceProbeEntry) = .empty;

var dev_list: DeviceList = undefined;

pub fn list_pci_devices() !void {
    dev_list.clearAndFree();
    try internal.list_devices(&dev_list);
}

fn on_pci_device_probe_bind(callback: *const anyopaque, ctx: ?*anyopaque) callconv(.c) bool {
    pci_probe_callbacks.append(allocator, .{
        .callback = @ptrCast(@alignCast(callback)),
        .context = ctx orelse return false,
    }) catch root.oom_panic();
    probe_single(
        @ptrCast(@alignCast(callback)),
        @ptrCast(@alignCast(ctx)),
    );
    return true;
}
fn on_pci_device_probe_unbind(callback: *const anyopaque) callconv(.c) void {
    for (pci_probe_callbacks.items, 0..) |i, idx| {
        if (@intFromPtr(i.callback) == @intFromPtr(callback)) {
            _ = pci_probe_callbacks.swapRemove(idx);
            break;
        }
    }
}

fn probe_all() void {
    for (pci_probe_callbacks.items) |probe_request| {
        probe_single(
            @ptrCast(@alignCast(probe_request.callback)),
            @ptrCast(@alignCast(probe_request.context)),
        );
    }
}
fn probe_single(func: DeviceProbeCallback, query: [*]const PciDeviceQuery) void {

    // It will iterate through all unbinded devices,
    // test the query and call the function if it matches

    var j: usize = 0;
    while (!query[j].isNull()) : (j += 1) {
        const q = query[j];

        for (dev_list.items) |dev| {
            if (!dev.binded) {
                if (q.get_vendor() != null and dev.addr.vendor_id().read() != q.vendor) continue;
                if (q.get_device() != null and dev.addr.device_id().read() != q.device) continue;
                if (q.get_class() != null and dev.addr.base_class().read() != q.class) continue;
                if (q.get_sub_class() != null and dev.addr.sub_class().read() != q.sub_class) continue;
                if (q.get_prog_if() != null and dev.addr.prog_if().read() != q.prog_if) continue;

                const res = func(dev);
                if (res) {
                    log.info("Device successfully binded by module!", .{});
                    dev.binded = true;
                }
            }
        }
    }
}

fn lspci() callconv(.c) void {
    log.info("Listing PCI devices:", .{});

    for (dev_list.items) |i| {
        log.info("{X:0>2}:{X:0>2}.{X:0>1} [{X:0>2}:{X:0>2}] {s}: [{X:0>4}] {s} - [{X:0>4}] {s}", .{ i.get_bus(), i.get_device(), i.get_function(), i.addr.base_class().read(), i.addr.sub_class().read(), i.type_str, i.addr.vendor_id().read(), i.vendor_str, i.addr.device_id().read(), i.name_str });
    }
}
