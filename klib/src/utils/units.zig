pub const UnitItem = struct { name: []const u8, limit: u128 };

pub const data = [_]UnitItem {
    .{ .name = "PiB", .limit = 1024 * 1024 * 1024 * 1024 * 1024 },
    .{ .name = "TiB", .limit = 1024 * 1024 * 1024 * 1024 },
    .{ .name = "GiB", .limit = 1024 * 1024 * 1024 },
    .{ .name = "MiB", .limit = 1024 * 1024 },
    .{ .name = "KiB", .limit = 1024 },
    .{ .name = "B",   .limit = 0 },
};

pub fn calc(bytes: usize, units: []const UnitItem) struct { f64, []const u8 } {
    var i: usize = 0;
    while (true) : (i += 1) if (bytes >= units[i].limit) break;

    const size_float: f64 = @floatFromInt(bytes);
    const unit_float: f64 = @floatFromInt(@max(1, units[i].limit));

    return .{ size_float / unit_float, units[i].name };
}
