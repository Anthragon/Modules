const std = @import("std");

// https://people.freebsd.org/~imp/asiabsdcon2015/works/d2161r5-ATAATAPI_Command_Set_-_3.pdf
pub const AtaIdentify = extern struct {
    words: [256]u16,

    pub fn isAtapi(self: *const AtaIdentify) bool {
        return (self.words[0] & (1 << 15)) != 0;
    }

    pub fn isSSD(self: *const AtaIdentify) bool {
        return self.words[217] == 1;
    }

    pub fn maxSectorsPerDrq(self: *const AtaIdentify) u8 {
        const w47 = self.words[47];
        if ((w47 & 0x8000) == 0) return 0;
        return @intCast(w47 & 0xff);
    }

    pub fn queueDepth(self: *const AtaIdentify) u8 {
        const w75 = self.words[75];
        return @intCast((w75 & 0x1f) + 1);
    }

    fn lba28(self: *const AtaIdentify) u32 {
        return (@as(u32, self.words[61]) << 16) | self.words[60];
    }

    fn lba48(self: *const AtaIdentify) u64 {
        return (@as(u64, self.words[103]) << 48) | (@as(u64, self.words[102]) << 32) |
            (@as(u64, self.words[101]) << 16) | self.words[100];
    }

    fn supportsLba48(self: *const AtaIdentify) bool {
        return (self.words[83] & (1 << 10)) != 0;
    }

    pub fn sectorCount(self: *const AtaIdentify) u64 {
        return if (self.supportsLba48()) self.lba48() else self.lba28();
    }

    pub fn logicalSectorSize(self: *const AtaIdentify) u32 {
        const w106 = self.words[106];
        if ((w106 & (1 << 12)) == 0) return 512;
        return (@as(u32, self.words[118]) << 16) | self.words[117];
    }
};
