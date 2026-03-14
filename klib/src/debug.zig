const std = @import("std");
const core = @import("core.zig");
const root = @import("root.zig");

const Writer = std.io.Writer;

pub var LogInfoWriter: Writer = .{
    .buffer = &.{},
    .vtable = &writerVtable,
};
const writerVtable: Writer.VTable = .{
    .drain = drain,
};

fn drain(_: *Writer, data: []const []const u8, splat: usize) error{WriteFailed}!usize {
    var bytesWritten: usize = 0;

    for (data[0..(data.len - 1)]) |i| {
        const buf = root.mem.allocator().alloc(u8, i.len + 1) catch return error.WriteFailed;
        defer root.mem.allocator().free(buf);

        @memcpy(buf[0..i.len], i);
        buf[i.len] = 0;
        core.log_raw(root.module_uuid, "debug", buf.ptr, buf.len);
        bytesWritten += i.len;
    }
    for (0..splat) |_| {
        const str = data[data.len - 1];
        core.log_raw(root.module_uuid, "debug", str.ptr, str.len);
        bytesWritten += str.len;
    }

    return bytesWritten;
}
