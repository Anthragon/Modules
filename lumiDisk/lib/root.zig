pub const core = @import("root").lib;
pub const DiskEntry = core.common.DiskEntry;
pub const PartEntry = core.common.PartEntry;

pub const interop = .{
    .DiskEntry = .{
        .read = @TypeOf(DiskEntry.c_read),
    },
    .PartitionEntry = .{
        .read = @TypeOf(PartEntry.c_read)
    }
};
