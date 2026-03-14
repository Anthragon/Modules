const root = @import("root.zig");
const Guid = root.Guid;
const Result = root.Result;

pub const RegisterDeviceInfo = extern struct {
    id: usize = 0,
    name: [*:0]const u8,
    identifier: Guid,
    specifier: usize,
    interface: Guid,
    flags: packed struct(u8) {
        canSee: u1,
        canReed: u1,
        canWrite: u1,

        _rsvd: u5 = 0,
    },
    status: enum(usize) {
        failed = 0,
        unset,

        unbinded,
        working,
    } = .unset,
};

const register_internal = @extern(
    ?*const fn (deviceInfoPtr: [*]RegisterDeviceInfo, deviceInfoCount: usize) callconv(.c) Result(void),
    .{ .name = "cap privileged_callable [00000000-0000-0000-0000-000000000000]Devices::register" },
) orelse unreachable;
pub fn register(devicesInfoPtr: [*]RegisterDeviceInfo, devicesInfoLen: usize) !void {
    return register_internal(devicesInfoPtr, devicesInfoLen).asbuiltin();
}
