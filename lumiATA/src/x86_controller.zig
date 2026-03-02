const std = @import("std");
const main = @import("main.zig");
const ports = @import("x86_ports.zig");

const Channel = main.Channel;
const Device = main.Device;

const ChannelsInfo = struct { io: u16, ctrl: u16, irq: u8 };
const channels = [_]ChannelsInfo {
    .{ .io = 0x1F0, .ctrl = 0x3F6, .irq = 14 },
    .{ .io = 0x170, .ctrl = 0x376, .irq = 15 },
};

const REG_DATA = 0;
const REG_SECCOUNT = 2;
const REG_LBA_LOW = 3;
const REG_LBA_MID = 4;
const REG_LBA_HIGH = 5;
const REG_HDDEVSEL = 6;
const REG_COMMAND = 7;
const REG_STATUS = 7;

const Cmd = enum(u8) {
    identify = 0xEC,
};

const SR_BSY = 0x80;
const SR_DRQ = 0x08;
const SR_ERR = 0x01;

var current_channel: ChannelsInfo = undefined;

pub fn select_channel(channel: Channel) void {
    switch (channel) {
        .primary => current_channel = channels[0],
        .secondary => current_channel = channels[1],
    }
}
pub fn select_device(device: Device) void {
    switch (device) {
        .master => ports.outb(current_channel.io + REG_HDDEVSEL, 0xA0),
        .slave => ports.outb(current_channel.io + REG_HDDEVSEL, 0xB0),
    }
}

pub fn select_lba(count: u8, lba: usize) void {
    ports.outb(current_channel.io + REG_SECCOUNT, count);
    ports.outb(current_channel.io + REG_LBA_LOW, @intCast(lba));
    ports.outb(current_channel.io + REG_LBA_MID, @intCast(lba >> 8));
    ports.outb(current_channel.io + REG_LBA_HIGH, @intCast(lba >> 16));
}

pub fn send_command(cmd: Cmd) void {
    ports.outb(current_channel.io + REG_COMMAND, @intFromEnum(cmd));
}
pub fn get_status() u8 {
    return ports.inb(current_channel.io + REG_STATUS);
}
pub fn read(buffer: []u16) void {
    for (0..buffer.len) |i| buffer[i] = ports.inw(current_channel.io + REG_DATA);
}
pub fn write(buffer: []const u16) void {
    for (0..buffer.len) |i| buffer[i] = ports.outw(current_channel.io, buffer[i]);
}
pub fn flush() void {
    ports.outb(current_channel.io + REG_COMMAND, 0xE7);
}

pub fn wait() !void {
    var dogwatch: isize = 1000;
    while (dogwatch > 0 and (ports.inb(current_channel.io + REG_STATUS) & SR_BSY) != 0) { dogwatch -= 1; }
    if (dogwatch <= 0) return error.Timeout;
    while (dogwatch > 0 and (ports.inb(current_channel.io + REG_STATUS) & SR_DRQ) == 0) { dogwatch -= 1; }
    if (dogwatch <= 0) return error.Timeout;
}

pub fn enable_irq() void {
    ports.outb(current_channel.ctrl, 0x00);
}
