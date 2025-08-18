pub const Addr = @import("Addr.zig").Addr;
pub const PciDevice = @import("PciDevice.zig").PciDevice;
pub const PciDeviceQuery = @import("PciDeviceQuery.zig").PciDeviceQuery;

pub const callables = .{
    .DeviceProbeCallback = *const fn(*PciDevice) callconv(.c) bool,
};
