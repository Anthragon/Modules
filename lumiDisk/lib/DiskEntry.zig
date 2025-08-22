pub const DiskEntry = extern struct {

    pub const ReadWriteHook = *const fn (ctx: ?*anyopaque, sector: usize, buffer: [*]u8, length: usize) callconv(.c) bool;
    pub const RemoveHook = *const fn (ctx: ?*anyopaque) callconv(.c) void;
    pub const VTable = extern struct {
        read: ReadWriteHook,
        write: ReadWriteHook,
        remove: RemoveHook,
    };
    const default_type: [:0]const u8 = "unk";

    /// host context
    context: ?*anyopaque,
    /// Virtual functions table associated with this entry
    vtable: *const VTable,

    /// The readable type name of the device
    /// e.g. `flash`, `cd`, `ssd`, `hhd`, `nvme`
    type: [*:0]const u8 = default_type,

    /// The disk length in sectors of 512 bytes
    sectors_length: usize,

    /// Disk's global identifier string
    /// e.g. disk's uuid in GPT disks
    global_identifier: [*:0]const u8,

    /// Partition entries for this disk entry
    partitions: [*]PartitionEntry = undefined,
    /// Partition entries length
    partitions_length: usize = 0,

    /// Performs a read operation
    pub fn read(s: @This(), sector: usize, buffer: []u8) !void {
        if (!s.vtable.read(s.context, sector, buffer.ptr, buffer.len)) return error.ReadFailed;
    }
    /// Performs a read operation (C compatibility version)
    pub fn c_read(s: @This(), sector: usize, buf_ptr: [*]u8, buf_len: usize) callconv(.c) bool {
        return s.vtable.read(s.context, sector, buf_ptr, buf_len);
    }
    // TODO write
    // TODO remove
    // TODO rescan

};

pub const PartitionEntry = extern struct {

    disk_parent: *DiskEntry,
    start_sector: usize,
    end_sector: usize,
    
    global_identifier: [*:0]const u8,
    readable_name: [*:0]const u8,

    /// Performs a read operation, offsetted to the partition base
    pub fn read(s: @This(), sector: usize, buffer: []u8) bool {
        if (sector + s.start_sector > s.end_sector) return false;
        s.disk_parent.read(s.start_sector + sector, buffer);
    }
    /// Performs a read operation, offsetted to the partition base (C compatibility version)
    pub fn c_read(s: @This(), sector: usize, buf_ptr: [*]u8, buf_len: usize) callconv(.c) bool {
        if (sector + s.start_sector > s.end_sector) return false;
        s.disk_parent.read(s.start_sector + sector, buf_ptr, buf_len);
    }

};
