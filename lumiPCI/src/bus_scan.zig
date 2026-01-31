const std = @import("std");
const root = @import("root");
const ports = root.system.ports;
const main = @import("main.zig");

const log = std.log.scoped(.@"bus scan");

pub const Addr = @import("Addr.zig").Addr;

const PciDevice = main.PciDevice;
const DeviceList = main.DeviceList;

// TODO implement PCI domains (Usually not present in PCs so not important by now)

pub fn list_devices(list: *DeviceList) !void {
    log.info("Scanning bus root...", .{});
    bus_scan(0, list);
    log.info("Scan complete! ({} devices found)", .{list.items.len});
}

fn bus_scan(bus: u8, list: *DeviceList) void {
    inline for (0..(1 << 5)) |device| {
        device_scan(bus, @intCast(device), list);
    }
}

fn device_scan(bus: u8, device: u5, list: *DeviceList) void {
    const nullfunc: Addr = .{ .bus = bus, .device = device, .function = 0 };

    if (nullfunc.header_type().read() == 0xFFFF) return;

    function_scan(
        nullfunc,
        list,
    ) catch |err| log.debug("Could not list device: {s}", .{@errorName(err)});

    if (nullfunc.header_type().read() & 0x80 == 0) return;

    inline for (0..((1 << 3) - 1)) |function| {
        function_scan(.{
            .bus = bus,
            .device = device,
            .function = @intCast(function + 1),
        }, list) catch |err| log.debug("Could not list device: {s}", .{@errorName(err)});
    }
}

fn function_scan(addr: Addr, list: *DeviceList) !void {
    if (addr.vendor_id().read() == 0xFFFF) return;

    // Append devices to the devices list
    // If bridge, iterate though it

    // Bridge device
    if (addr.base_class().read() == 0x06) {
        var still_unrecognized = false;

        switch (addr.sub_class().read()) {
            0x00 => log.debug("found Host bridge (ignoring)", .{}),
            0x04 => {
                log.debug("found PCI-to-PCI bridge", .{});
                if ((addr.header_type().read() & 0x7F) == 0x01) {
                    const secondary_bus = addr.secondary_bus().read();
                    log.debug("    recursively scanning bus {0X}", .{secondary_bus});
                    bus_scan(secondary_bus, list);
                }
            },
            else => still_unrecognized = true,
        }

        if (!still_unrecognized) return;
    }

    log.debug(
        "PCI device {x:0>4}:{x:0>4}:{x:0>4} - class: {x:0>4} subclass: {x:0>4}",
        .{ addr.bus, addr.device, addr.function, addr.base_class().read(), addr.sub_class().read() },
    );

    const new_device = try main.allocator.create(PciDevice);
    errdefer main.allocator.destroy(new_device);

    var deviceInfo: main.RegisterDeviceInfo = .{
        .name = PciDevice.default_name,
        .identifier = .zero(),
        .specifier = 0,
        .interface = .fromComptimeString("e2e46cb0-9331-4e9f-92cd-c99a9d603be7"),
        .flags = .{
            .canSee = 1,
            .canReed = 0,
            .canWrite = 0,
        },
    };
    try main.register_devices(@ptrCast(&deviceInfo), 1).asbuiltin();
    new_device.* = .{ .dev_id = deviceInfo.id, .addr = addr };

    try list.append(main.allocator, new_device);
}
