pub const PciDeviceQuery = extern struct {
    vendor: u16,
    device: u16,
    sub_vendor: u16,
    sub_device: u16,
    class: u8,
    sub_class: u8,
    prog_if: u8,

    pub fn byClass(class: u8, subclass: u8, prog_if: u8) @This() {
        return .{
            .vendor = 0xffff,
            .device = 0xffff,
            .sub_vendor = 0xffff,
            .sub_device = 0xffff,
            .class = class,
            .sub_class = subclass,
            .prog_if = prog_if,
        };
    }
    pub fn byVendor(vendor: u16, sub_vendor: u16, dev: u16, sub_dev: u16) @This() {
        return .{
            .vendor = vendor,
            .device = dev,
            .sub_vendor = sub_vendor,
            .sub_device = sub_dev,
            .class = 0,
            .sub_class = 0,
            .prog_if = 0,
        };
    }

    pub fn endOfChain() @This() {
        return .{
            .vendor = 0,
            .device = 0,
            .sub_vendor = 0,
            .sub_device = 0,
            .class = 0,
            .sub_class = 0,
            .prog_if = 0,
        };
    }
    pub fn isNull(s: @This()) bool {
        return s.vendor == 0;
    }
    
    pub inline fn get_vendor(s: @This()) ?u16 { return if (s.vendor == 0xffff) null else s.vendor; }
    pub inline fn get_device(s: @This()) ?u16 { return if (s.device == 0xffff) null else s.device; }
    pub inline fn get_sub_vendor(s: @This()) ?u16 { return if (s.sub_vendor == 0xffff) null else s.sub_vendor; }
    pub inline fn get_sub_device(s: @This()) ?u16 { return if (s.sub_device == 0xffff) null else s.sub_device; }
    pub inline fn get_class(s: @This()) ?u8 { return if (s.class == 0) null else s.class; }
    pub inline fn get_sub_class(s: @This()) ?u8 { return if (s.sub_class == 0) null else s.sub_class; }
    pub inline fn get_prog_if(s: @This()) ?u8 { return if (s.prog_if == 0) null else s.prog_if; }

    pub fn format(s: *const @This(), comptime _: []const u8, _: @import("std").fmt.FormatOptions, fmt: anytype) !void {
        try fmt.writeAll("PCI Querry: ");

        if (s.vendor == 0xffff) try fmt.print("****:", .{}) else try fmt.print("{x:0>4}:", .{s.vendor});
        if (s.sub_vendor == 0xffff) try fmt.print("****.", .{}) else try fmt.print("{x:0>4}.", .{s.sub_vendor});
        if (s.device == 0xffff) try fmt.print("****:", .{}) else try fmt.print("{x:0>4}:", .{s.device});
        if (s.sub_device == 0xffff) try fmt.print("**** ", .{}) else try fmt.print("{x:0>4} ", .{s.sub_device});

        if (s.class == 0) try fmt.print("[**:", .{}) else try fmt.print("[{x:0>2}:", .{s.class});
        if (s.sub_class == 0) try fmt.print("**:", .{}) else try fmt.print("{x:0>2}:", .{s.sub_class});
        if (s.prog_if == 0) try fmt.print("**]", .{}) else try fmt.print("{x:0>2}]", .{s.prog_if});
    }
};
