const root = @import("root.zig");
const Guid = root.Guid;
const Result = root.Result;
const kernel = @import("kernel");

pub const RegisterInfo = kernel.common.devices.RegisterInfo;
pub const Device = kernel.common.devices.Device;
pub const VTable = kernel.common.devices.VTable;

const register_internal = @extern(
    ?*const fn (deviceInfoPtr: [*]RegisterInfo, deviceInfoCount: usize) callconv(.c) Result(void),
    .{ .name = "cap [00000000-0000-0000-0000-000000000000] PC Devices::register" },
) orelse unreachable;
pub fn register(devicesInfoPtr: [*]RegisterInfo, devicesInfoLen: usize) !void {
    return register_internal(devicesInfoPtr, devicesInfoLen).asbuiltin();
}

extern fn @"cap [00000000-0000-0000-0000-000000000000] PC Devices::foreach_devices"(devInfo: *?*const Device, identifier: Guid, specifier: usize, interface: Guid) callconv(.c) Result(bool);
pub fn foreach_devices(devInfo: *?*const Device, identifier: Guid, specifier: usize, interface: Guid) !bool {
    return try @"cap [00000000-0000-0000-0000-000000000000] PC Devices::foreach_devices"(
        devInfo,
        identifier,
        specifier,
        interface,
    ).asbuiltin();
}
