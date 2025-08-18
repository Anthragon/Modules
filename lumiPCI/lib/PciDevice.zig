const root = @import("main.zig");

pub const PciDevice = extern struct {

    const default_string: [*:0]const u8 = "unknown";

    addr: root.Addr,

    type_str: [*:0]const u8 = default_string,
    vendor_str: [*:0]const u8 = default_string,
    name_str: [*:0]const u8 = default_string,

    binded: bool = false,

    pub inline fn get_bus(s: @This()) u8 { return s.addr.bus; }
    pub inline fn get_device(s: @This()) u5 { return s.addr.device; }
    pub inline fn get_function(s: @This()) u3 { return s.addr.function; }

};
