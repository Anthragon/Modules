const std = @import("std");
const root = @import("root");
const lib = @import("lib");
const ports = root.system.ports;
const debug = root.debug;
const main = @import("../main.zig");

const log = std.log.scoped(.@"lumiPCI x86_64");

pub const Addr = lib.Addr;

const PciDevice = main.PciDevice;
const DeviceList = main.DeviceList;

// TODO implement PCI domains (Usually not present in PCs but meh)

pub fn list_devices(list: *DeviceList) !void {

    log.info("Scanning bus root...", .{});
    bus_scan(0, list);
    log.info("Scan complete! ({} devices found)", .{ list.items.len });

}


fn bus_scan(bus: u8, list: *DeviceList) void {
    inline for (0..(1 << 5)) |device| {
        device_scan(bus, @intCast(device), list);
    }
}

pub fn device_scan(bus: u8, device: u5, list: *DeviceList) void {
    const nullfunc: Addr = .{ .bus = bus, .device = device, .function = 0 };

    if (nullfunc.header_type().read() == 0xFFFF) return;

    function_scan(nullfunc, list) catch |err| log.debug("Could not list device: {s}", .{@errorName(err)});

    if (nullfunc.header_type().read() & 0x80 == 0) return;

    inline for (0..((1 << 3) - 1)) |function| {
        function_scan(.{ .bus = bus, .device = device, .function = @intCast(function + 1) }, list)
            catch |err| log.debug("Could not list device: {s}", .{@errorName(err)});
    }
}

pub fn function_scan(addr: Addr, list: *DeviceList) !void {
    if (addr.vendor_id().read() == 0xFFFF) return;

    // Append devices to the devices list
    // If bridge, iterate though it

    // Bridge device
    if (addr.base_class().read() == 0x06) {

        var still_unrecognized = false;

        switch (addr.sub_class().read()) {
            0x00 => log.debug("Host bridge (ignoring)", .{}),
            0x04 => {
                log.debug("PCI-to-PCI bridge", .{});
                if ((addr.header_type().read() & 0x7F) != 0x01) {

                    log.debug(" (Not PCI-to-PCI bridge header type!)", .{});

                } else {

                    const secondary_bus = addr.secondary_bus().read();
                    log.debug(", recursively scanning bus {0X}", .{secondary_bus});
                    bus_scan(secondary_bus, list);
                    
                }
            },
            else => still_unrecognized = true
        }

        if (!still_unrecognized) return;
    }

    const new_device = try list.allocator.create(PciDevice);
    errdefer list.allocator.destroy(new_device);
    new_device.* = .{ .addr = addr };
    try list.append(new_device);

}

