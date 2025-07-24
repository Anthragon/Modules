const std = @import("std");
const root = @import("root");

const disk = root.devices.disk;
const DiskEntry = disk.DiskEntry;

pub fn analyze(sector: []const u8, entry: *DiskEntry) !void {
    _ = sector;
    _ = entry;

    return error.NotImplemented;
}
