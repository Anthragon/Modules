const std = @import("std");
const root = @import("root");

const disk = root.devices.disk;
const DiskInfo = disk.DiskInfo;

pub fn analyze(sector: []const u8, entry: *DiskInfo) !void {
    _ = sector;
    _ = entry;

    return error.NotImplemented;
}
