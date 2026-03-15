const root = @import("main.zig");
const klib = @import("klib");
const Result = klib.Result;
const Device = root.DevInfo;

pub fn control(device: *anyopaque, ctlPtr: [*]usize, ctlLen: usize) callconv(.c) Result(usize) {
    const dev: *Device = @ptrCast(@alignCast(device));
    var i: usize = 0;
    var j: usize = 0;

    while (j < ctlLen) {
        switch (ctlPtr[i]) {
            0xd14a028c2a3a2bc9 => {
                const req: *BlkDevRequestRead = @ptrCast(@alignCast(&ctlPtr[i]));
                requestRead(
                    dev,
                    req.logicalSector,
                    req.destinyBufferPtr[0..req.destinyBufferLen],
                ) catch |err| return .frombuiltin(err);
                i += @sizeOf(BlkDevRequestRead);
            },

            0x9350828c49590226 => {
                @panic("TODO: Request write");
            },

            else => return .err(.invalidValue),
        }
        j += 1;
    }

    return .val(0);
}

pub const BlkDevRequestRead = extern struct {
    magic: u64 = 0xd14a028c2a3a2bc9,
    logicalSector: usize,
    destinyBufferPtr: [*]u8,
    destinyBufferLen: usize,
};
pub fn requestRead(device: *const Device, lba: usize, destiny: []u8) !void {
    _ = device;
    _ = lba;
    _ = destiny;
}

pub const BlkDevRequestWrite = extern struct {
    magic: u64 = 0x9350828c49590226,
    logicalSector: usize,
    destinyBufferPtr: [*]u8,
    destinyBufferLen: usize,
};
