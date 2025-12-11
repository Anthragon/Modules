const builtin = @import("builtin");
const arch = builtin.cpu.arch;

pub const Addr = @import("Addr.zig").Addr;
pub const PciDevice = @import("PciDevice.zig").PciDevice;
pub const PciDeviceQuery = @import("PciDeviceQuery.zig").PciDeviceQuery;

pub const callables = .{
    .DeviceProbeCallback = *const fn (*PciDevice) callconv(.c) bool,
};

pub const x86_ports = switch (arch) {
    .x86, .x86_64 => @import("x86/ports.zig"),
    else => unreachable,
};
