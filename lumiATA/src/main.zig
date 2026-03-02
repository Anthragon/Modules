const std = @import("std");
const klib = @import("klib");
const builtin = @import("builtin");
const capabilities = klib.capabilities;
const Result = klib.Result;
const Guid = klib.Guid;

pub const std_options = klib.std_oprions;
pub var vtable: klib.KernelVTable = .{ .abi_version = 1 };

// Module information
const module_info = @"6f5b62fb-e787-4344-985d-a54ca856e8d9_module-info";
export const @"6f5b62fb-e787-4344-985d-a54ca856e8d9_module-info" linksection(".kernel_modules") = klib.Module{
    .name = "lumiATA",
    .version = "0.1.0",
    .author = "lumi2021",
    .license = "MPL-2.0",
    .flags = .{ .needs_privilege = true },
    .uuid = klib.Guid.fromString("6f5b62fb-e787-4344-985d-a54ca856e8d9") catch unreachable,
    .init = @ptrCast(&init),
    .deinit = @ptrCast(&deinit),
};

const controller = switch(builtin.cpu.arch) {
    .x86_64 => @import("x86_controller.zig"),
    else => undefined
};
pub const Channel = enum { primary, secondary };
pub const Device = enum { master, slave };

const log = std.log.scoped(.main);
pub var allocator: std.mem.Allocator = undefined;

var device_status: []bool = .{ false, false, false, false };

pub fn init() callconv(.c) bool {
    klib.module_uuid = module_info.uuid;
    log.info("Hello, lumiATA!", .{});

    allocator = klib.mem.allocator();

    enumerate_devices();

    return true;
}
pub fn deinit() callconv(.c) void {}


pub fn enumerate_devices() void {
    var response_buffer: [512]u8 = undefined;
    
    controller.select_channel(.primary);
    if (controller.get_status() != 0xff) {
        log.info("Found primary channel. Identifing devices...", .{});
        identify(.primary, .master, &response_buffer) catch log.info("Timeout!", .{});
    }

    controller.select_channel(.secondary);
    if (controller.get_status() != 0xff) {
        log.info("Found secondary channel. Identifing devices...", .{});
        identify(.secondary, .master, &response_buffer) catch log.info("Timeout!", .{});
    }
}


pub fn identify(channel: Channel, device: Device, buffer: *[512]u8) !void {
    controller.select_channel(channel);
    controller.select_device(device);

    controller.select_lba(0, 0);
    controller.send_command(.identify);

    const status = controller.get_status();
    if (status == 0) return error.NoResponse;

    try controller.wait();
    controller.read(@as([*]u16, @alignCast(@ptrCast(buffer)))[0..256]);
    controller.flush();
}


pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    var buf: [128]u8 = undefined;
    const str = std.fmt.bufPrintZ(&buf, "{s}", .{msg}) catch unreachable;
    klib.kernel_panic(str);
}
