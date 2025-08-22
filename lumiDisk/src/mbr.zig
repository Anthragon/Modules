const std = @import("std");
const root = @import("root");
const lib = @import("lib");

const DiskEntry = lib.DiskEntry;

pub fn analyze(sector: []const u8, entry: *DiskEntry) !void {
    _ = sector;
    _ = entry;

    return error.NotImplemented;
}
