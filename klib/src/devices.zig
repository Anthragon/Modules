const root = @import("root.zig");
const Guid = root.Guid;
const Result = root.Result;
const kernel = @import("kernel");

pub const RegisterInfo = kernel.common.devices.RegisterInfo;
pub const VTable = kernel.common.devices.VTable;

const register_internal = @extern(
    ?*const fn (deviceInfoPtr: [*]RegisterInfo, deviceInfoCount: usize) callconv(.c) Result(void),
    .{ .name = "cap privileged_callable [00000000-0000-0000-0000-000000000000]Devices::register" },
) orelse unreachable;
pub fn register(devicesInfoPtr: [*]RegisterInfo, devicesInfoLen: usize) !void {
    return register_internal(devicesInfoPtr, devicesInfoLen).asbuiltin();
}
