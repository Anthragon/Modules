const port = @import("root.zig").x86_ports;

pub const regoff = u8;

pub const Addr = packed struct {
    bus: u8,
    device: u5,
    function: u3,

    pub const vendor_id = cfgreg(u16, 0x00);
    pub const device_id = cfgreg(u16, 0x02);
    pub const command = cfgreg(u16, 0x04);
    pub const status = cfgreg(u16, 0x06);
    pub const prog_if = cfgreg(u8, 0x09);
    pub const header_type = cfgreg(u8, 0x0E);
    pub const base_class = cfgreg(u8, 0x0B);
    pub const sub_class = cfgreg(u8, 0x0A);
    pub const secondary_bus = cfgreg(u8, 0x19);
    pub const cap_ptr = cfgreg(u8, 0x34);
    pub const int_line = cfgreg(u8, 0x3C);
    pub const int_pin = cfgreg(u8, 0x3D);

    pub fn barinfo(self: @This(), bar_idx: u8) BarInfo {
        var orig: u64 = self.read(u32, 0x10 + bar_idx * 4) & 0xFFFFFFF0;
        self.write(u32, 0x10 + bar_idx * 4, 0xFFFFFFFF);
        const pci_out = self.read(u32, 0x10 + bar_idx * 4);
        const is64 = ((pci_out & 0b110) >> 1) == 2; // bits 1:2, bar type (0 = 32bit, 1 = 64bit)

        self.write(u32, 0x10 + bar_idx * 4, @truncate(orig));

        var response: u64 = @as(u64, pci_out & 0xFFFFFFF0);
        if (is64) {
            orig |= @as(u64, self.read(u32, 0x14 + bar_idx * 4)) << 32;
            self.write(u32, 0x14 + bar_idx * 4, 0xFFFFFFFF); // 64bit bar = two 32-bit bars
            response |= @as(u64, self.read(u32, 0x14 + bar_idx * 4)) << 32;
            self.write(u32, 0x14 + bar_idx * 4, @truncate(orig >> 32));
            return .{ .phy = orig, .size = ~response +% 1 };
        } else {
            return .{ .phy = orig, .size = (~response +% 1) & 0xFFFFFFFF };
        }
    }

    pub fn read(self: @This(), comptime T: type, offset: regoff) T {
        pci_space_request(self, offset);
        return port.in(T, 0xCFC + @as(u16, offset % 4));
    }

    pub fn write(self: @This(), comptime T: type, offset: regoff, value: T) void {
        pci_space_request(self, offset);
        return port.out(T, 0xCFC + @as(u16, offset % 4), value);
    }

    pub const BarInfo = struct {
        phy: u64,
        size: u64,
    };

    fn cfgreg(comptime T: type, comptime off: regoff) fn (self: @This()) PciFn(T, off) {
        return struct {
            fn function(self: Addr) PciFn(T, off) {
                return .{ .self = self };
            }
        }.function;
    }

    fn PciFn(comptime T: type, comptime off: regoff) type {
        return struct {
            self: Addr,
            pub fn read(self: @This()) T {
                return self.self.read(T, off);
            }
            pub fn write(self: @This(), val: T) void {
                self.self.write(T, off, val);
            }
        };
    }

    fn pci_space_request(addr: @This(), offset: regoff) void {
        const val = 1 << 31 | @as(u32, offset) | @as(u32, addr.function) << 8 | @as(u32, addr.device) << 11 | @as(u32, addr.bus) << 16;
        port.outl(0xCF8, val);
    }
};
