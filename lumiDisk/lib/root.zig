pub const DiskEntry = @import("DiskEntry.zig").DiskEntry;
pub const PartitionEntry = @import("DiskEntry.zig").PartitionEntry;

pub const interop = .{
    .DiskEntryWrapper = @import("interop/DirEntryWrapper.zigq").DiskEntryWrapper
};
