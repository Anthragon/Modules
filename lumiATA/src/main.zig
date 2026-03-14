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

const controller = switch (builtin.cpu.arch) {
    .x86_64 => @import("x86_controller.zig"),
    else => undefined,
};
pub const Channel = enum { primary, secondary };
pub const Device = enum { master, slave };

pub const DevInfo = struct {
    channel: Channel,
    device: Device,
    sectorCount: usize,
};
pub const AtaIdentify = @import("AtaIdentify.zig").AtaIdentify;

const log = std.log.scoped(.main);
pub var allocator: std.mem.Allocator = undefined;

var devices: [4]?DevInfo = .{ null, null, null, null };

pub fn init() callconv(.c) bool {
    klib.module_uuid = module_info.uuid;
    log.info("Hello, lumiATA!", .{});

    allocator = klib.mem.allocator();

    enumerate_devices();

    return true;
}
pub fn deinit() callconv(.c) void {}

pub fn enumerate_devices() void {
    var ata_id: AtaIdentify = undefined;

    controller.select_channel(.primary);
    if (controller.get_status() != 0xff) {
        log.debug("Found primary channel. Identifing devices...", .{});

        var res = identify(.primary, .master, &ata_id);
        if (res) |_| {
            log.debug("Primary master found", .{});
            append_device(.primary, .master, &ata_id);
        } else |_| {}

        res = identify(.primary, .slave, &ata_id);
        if (res) {
            log.debug("Primary slave found", .{});
            append_device(.primary, .slave, &ata_id);
        } else |_| {}
    }

    controller.select_channel(.secondary);
    if (controller.get_status() != 0xff) {
        log.debug("Found secondary channel. Identifing devices...", .{});

        var res = identify(.secondary, .master, &ata_id);
        if (res) {
            log.debug("Secondary master found", .{});
            append_device(.secondary, .master, &ata_id);
        } else |_| {}

        res = identify(.secondary, .slave, &ata_id);
        if (res) {
            log.debug("Secondary slave found", .{});
            append_device(.secondary, .slave, &ata_id);
        } else |_| {}
    }
}
fn append_device(channel: Channel, device: Device, identifyStruct: *AtaIdentify) void {
    const devid = getIndex(channel, device);
    devices[devid] = .{
        .channel = channel,
        .device = device,
        .sectorCount = identifyStruct.sectorCount(),
    };

    var devInfo = klib.devices.RegisterDeviceInfo{
        .name = "IDE disk drive",
        .flags = .{
            .canReed = 0,
            .canSee = 1,
            .canWrite = 0,
        },
        .interface = .zero(),
        .identifier = .fromComptimeString("7246d220-ac0b-4e45-872b-b67e0d84deae"),
        .specifier = 0x0,
    };

    klib.devices.register(@ptrCast(&devInfo), 1) catch {
        devices[devid] = null;
    };
}

pub fn identify(channel: Channel, device: Device, identifyStruct: *AtaIdentify) !void {
    controller.select_channel(channel);
    controller.select_device(device);

    controller.select_lba(0, 0);
    controller.send_command(.identify);

    const status = controller.get_status();
    if (status == 0) return error.NoResponse;

    try controller.wait();
    controller.read(&identifyStruct.words);
    controller.flush();
}

fn getIndex(channel: Channel, device: Device) usize {
    return std.math.shl(usize, @intFromEnum(channel), 1) + @intFromEnum(device);
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    var buf: [128]u8 = undefined;
    const str = std.fmt.bufPrintZ(&buf, "{s}", .{msg}) catch unreachable;
    klib.kernel_panic(str);
}
