const std = @import("std");
const root = @import("root");
const modules = root.modules;
const sys = root.system;
const debug = root.debug;
const pci = root.devices.pci;

const PciDevice = pci.PciDevice;

const allocator = root.mem.heap.kernel_buddy_allocator;

const sata = @import("sata.zig");

// Module information
pub const module_name: [*:0]const u8 =     "elvaAHCI";
pub const module_version: [*:0]const u8 =  "0.1.0";
pub const module_author: [*:0]const u8 =   "System Elva Team";
pub const module_liscence: [*:0]const u8 = "MPL-2.0";

pub fn init() callconv(.c) bool {
    debug.print("Hello, elvaAHCI!\n", .{});

    const query: [*]const pci.PciDeviceQuery = &[_]pci.PciDeviceQuery {
        .byClass(0x01, 0x06, 0), // SATA controller class
        .endOfChain()
    };

    debug.print("Probing PCI devices...\n", .{});
    pci.pci_device_probe(query, device_probe);

    root.devices.disk.lsblk();

    var buf: [512]u8 = undefined;
    root.devices.disk.get_disk_by_idx(0).?.read(0, &buf) catch unreachable;
    debug.dumpHex(&buf);

    debug.print("Returning...\n", .{});
    return true;
}
pub fn deinit() callconv(.c) void {

}
pub fn device_probe(dev: *PciDevice) callconv(.c) bool {

    // It will swith-case by the vendor and device to
    // assign the correct names to it
    name_device(dev);

    debug.print("Probing PCI device: {X:0>2}:{X:0>2}.{X:0>1} [{X:0>2}:{X:0>2}] {s}\n", .{
        dev.get_bus(),
        dev.get_device(),
        dev.get_function(),
        dev.addr.base_class().read(),
        dev.addr.sub_class().read(),
        dev.name_str,
    });
    
    const bar_info = dev.addr.barinfo(5);
    debug.print("Bar info: ptr: {X}, size: {} bytes\n", .{bar_info.phy, bar_info.size});
    const bar_size_aligned = std.mem.alignForward(usize, bar_info.size, sys.pmm.page_size);

    const allocation = root.mem.heap.kernel_page_allocator.request_space(bar_size_aligned);

    // Remapping pages
    root.system.mem_paging.map_range(bar_info.phy, allocation, bar_size_aligned, .{
        .disable_cache = true,
        .execute = false,
        .privileged = true,
        .read = true,
        .write = true,
        .lock = true
    })
    catch |err| {
        // Mapping error! free the allocation and return false
        root.mem.heap.kernel_page_allocator.free_space(bar_info.size);
        root.debug.print("Error! {s}\n", .{ @errorName(err) });
        return false;
    };

    const abar: *HBAMem = @ptrFromInt(allocation);
    iterate_ports(abar);

    return true;
}

pub fn find_cmdslot(port: *HBAPort, cmdslots: usize) isize {
    var slots = (port.sact | port.ci);
    for (0..cmdslots) |i| {
        if ((slots & 1) == 0) return @bitCast(i);
        slots >>= 1;
    }

    debug.err("Cannot find a free command list entry\n", .{});
    return -1;
}

fn iterate_ports(abar: *HBAMem) void {

    debug.print("Iterate though aHCI ports...\n", .{});

    // Search disk in implemented ports
    var pi: u32 = abar.pi;
    var i: usize = 0;
    while (i < 32) : ({i += 1; pi >>= 1;}) {

         if (pi & 1 != 0) {
            
            const port = abar.ports(i);
            const dt = check_type(port);
            if (dt == .sata) {
                debug.err("SATA drive found in port {}\n", .{i});
                sata.init_disk(abar, port) catch debug.err("Error while initializing SATA\n", .{});
            }
            else if (dt == .satapi) debug.err("SATAPI drive found in port {}\n", .{i})
            else if (dt == .semb) debug.err("SEMB drive found in port {}\n", .{i})
            else if (dt == .pm) debug.err("PM drive found in port {}\n", .{i});
        }

    }

}


fn check_type(port: *HBAPort) AHCIDevice {
    const ssts = port.ssts;
    const ipm = (ssts >> 8) & 0x0F;
    const det = ssts & 0x0F;

    if (det != 3) return ._null;
    if (ipm != 1) return ._null;

    return switch (port.sig) {
        0xEB140101 => .satapi,
        0xC33C0101 => .semb,
        0x96690101 => .pm,
        else => .sata
    };
}


fn name_device(dev: *PciDevice) void {

    dev.type_str = "SATA Controller";
    switch (dev.addr.vendor_id().read()) {
        else => |v| debug.err("Unknown vendor ID {X:0>4}", .{v}),

        0x8086 => {
            dev.vendor_str = "Intel";
            switch (dev.addr.device_id().read()) {
                else => |v| debug.err("Unknown device ID {X:0>4} from vendor {s}", .{v, dev.vendor_str}),

                0x06d2,
                0x02d3 => dev.name_str = "Comet Lake SATA AHCI Controller",

                0x0f22,
                0x0f23 => dev.name_str = "Atom Processor E3800 Series SATA AHCI Controller",

                0x1bd2,
                0x1bf2 => dev.name_str = "Sapphire Rapids SATA AHCI Controller",

                0x1c02,
                0x1c03 => dev.name_str = "Intel 6 Series/C200 Series Chipset Family SATA AHCI Controller",
                0x8c02 => dev.name_str = "Intel 8 Series/C220 Chipset Family SATA Controller 1 [AHCI mode]",
                0x9c03 => dev.name_str = "Intel 9 Series Chipset Family SATA Controller [AHCI Mode]",

                0x1d02 => dev.name_str = "C600/X79 series chipset 6-Port SATA AHCI Controller",

                0x1e02 => dev.name_str = "7 Series/C210 Series Chipset Family 6-port SATA Controller [AHCI mode]",
                0x1e03 => dev.name_str = "7 Series Chipset Family 6-port SATA Controller [AHCI mode]",

                0x1f22,
                0x1f23 => dev.name_str = "Atom processor C2000 AHCI SATA2 Controller",
                0x1f32,
                0x1f33 => dev.name_str = "Atom processor C2000 AHCI SATA3 Controller",

                0x22a4 => dev.name_str = "Atom/Celeron/Pentium Processor x5-E8000/J3xxx/N3xxx Series SATA AHCI Controller",
                0x2323 => dev.name_str = "DH89xxCC 4 Port SATA AHCI Controller",
                0x23a3 => dev.name_str = "DH895XCC Series 4-Port SATA Controller [AHCI Mode]",
                
                0x2681 => dev.name_str = "631xESB/632xESB SATA AHCI Controller",

                0x27c1 => dev.name_str = "NM10/ICH7 Family SATA Controller [AHCI mode]",
                0x27c5 => dev.name_str = "82801GBM/GHM (ICH7-M Family) SATA Controller [AHCI mode]",

                0x2821 => dev.name_str = "82801HR/HO/HH (ICH8R/DO/DH) 6 port SATA Controller [AHCI mode]",
                0x2824 => dev.name_str = "82801HB (ICH8) 4 port SATA Controller [AHCI mode]",
                0x2829 => dev.name_str = "82801HM/HEM (ICH8M/ICH8M-E) SATA Controller [AHCI mode]",

                0x2922 => dev.name_str = "Intel ICH9 SATA Controller [AHCI mode]",
                0x2923 => dev.name_str = "82801IB (ICH9) 4 port SATA Controller [AHCI mode]",
                0x2929 => dev.name_str = "82801IBM/IEM (ICH9M/ICH9M-E) 4 port SATA Controller [AHCI mode]",

                0x34de => dev.name_str = "Ice Lake-LP SATA Controller [AHCI mode]",

                0x9c83 => dev.name_str = "Wildcat Point-LP SATA Controller [AHCI Mode]",

            }
        },

        0x1022 => {
            dev.vendor_str = "AMD";
            switch (dev.addr.device_id().read()) {
                else => |v| debug.err("Unknown device ID {X:0>4} from vendor {s}", .{v, dev.vendor_str}),

                0x7801 => dev.name_str = "AMD FCH SATA Controller [AHCI mode]",
                0x4391 => dev.name_str = "AMD SB7x0/SB8x0/SB9x0 SATA Controller [AHCI mode]"

            }
        },

        0x1b21 => {
            dev.vendor_str = "ASMedia Technology Inc.";
            switch (dev.addr.device_id().read()) {
                else => |v| debug.err("Unknown device ID {X:0>4} from vendor {s}", .{v, dev.vendor_str}),

                0x0612 => dev.name_str = "ASMedia ASM1062 Serial ATA Controller",
                0x0611 => dev.name_str = "ASMedia ASM1061 SATA Controller"

            }
        },

        0x1b4b => {
            dev.vendor_str = "Marvell Technology Group Ltd.";
            switch (dev.addr.device_id().read()) {
                else => |v| debug.err("Unknown device ID {X:0>4} from vendor {s}", .{v, dev.vendor_str}),

                0x9123 => dev.name_str = "Marvell 88SE9123 PCIe SATA 6 Gb/s Controller",
                0x9230 => dev.name_str = "Marvell 88SE9230 PCIe SATA 6 Gb/s Controller"

            }
        },

    }

}


pub const AHCIDevice = enum {
    _null,
    sata,
    semb,
    pm,
    satapi
};

pub const FISType = enum(u8) {
    FIS_TYPE_REG_H2D	= 0x27,	// Register FIS - host to device
	FIS_TYPE_REG_D2H	= 0x34,	// Register FIS - device to host
	FIS_TYPE_DMA_ACT	= 0x39,	// DMA activate FIS - device to host
	FIS_TYPE_DMA_SETUP	= 0x41,	// DMA setup FIS - bidirectional
	FIS_TYPE_DATA		= 0x46,	// Data FIS - bidirectional
	FIS_TYPE_BIST		= 0x58,	// BIST activate FIS - bidirectional
	FIS_TYPE_PIO_SETUP	= 0x5F,	// PIO setup FIS - device to host
	FIS_TYPE_DEV_BITS	= 0xA1,	// Set device bits FIS - device to host
};
pub const AHCIDeviceEntry = struct {
    kind: AHCIDevice,
    abar: *HBAMem,
    port: *HBAPort,
};

// FIS register - Host to Device
pub const FIS_Reg_H2D = packed struct {
    fis_type: u8,
    pmport: u4,
    _reserved_0: u3 = 0,
    c: u1,

    command: u8,
    featurel: u8,

    lba0: u8,
    lba1: u8,
    lba2: u8,
    device: u8,

    lba3: u8,
    lba4: u8,
    lba5: u8,
    featureh: u8,

    countl: u8,
    counth: u8,
    icc: u8,
    control: u8,

    _reserved_1: u64 = 0
};
// FIS register - Device to Host
pub const FIS_Reg_D2H = packed struct {
    fis_type: u8,
    pmport: u4,
    _reserved_0: u2,
    i: u1,
    _reserved_1: u1,

    status: u8,
    @"error": u8,

    lba0: u8,
    lba1: u8,
    lba2: u8,
    device: u8,

    lba3: u8,
    lba4: u8,
    lba5: u8,
    _reserved_2: u8,

    countl: u8,
    counth: u8,
    _reserved_3: u16,
    _reserved_4: u64
};

pub const FISData = packed struct {
    fis_type: u8,
    pmport: u4,
    _reserved_0: u4,
    _reserved_1: u16,
    __data__: u32,

    pub fn data(s: *@This()) [*]u32 {
        return @ptrCast(&s.__data__);
    }
};
pub const FISPIOSetup = packed struct {
    fis_type: u8,

    pmport: u4,
    _reserved_0: u1,
    d: u1,

    i: u1,
    _reserved_1: u1,

    status: u8,
    @"error": u8,

    lba0: u8,
    lba1: u8,
    lba2: u8,
    device: u8,

    lba3: u8,
    lba4: u8,
    lba5: u8,
    _reserved_2: u8,

    countl: u8,
    counth: u8,
    _reserved_3: u8,
    e_status: u8,

    tc: u16,
    _reserved_4: u16
};
pub const FISDMASetup = packed struct {
    fis_type: u8,

    pmport: u4,
    _reserved_0: u1,
    d: u1,

    i: u1,
    a: u1,

    _reserved_1: u16,
    DMAbufferID: u64,

    _reserved_2: u32,

    DMAbufferOffset: u32,

    TransferCount: u32,

    _reserved_3: u32
};

pub const HBAMem = extern struct {
    cap: u32,
    ghc: u32,
    is: u32,
    pi: u32,
    vs: u32,
    ccc_ctl: u32,

    ccc_pts: u32,
    em_loc: u32,
    em_ctl: u32,
    cap2: u32,
    bohc: u32,

    // 0x2C - 0x9F, Reserved
    _reserved_0: [116]u8,

    vendor: [96]u8,

    __ports__: HBAPort,

    pub fn ports(s: *@This(), i: usize) *HBAPort {
        return &@as([*]HBAPort, @ptrCast(&s.__ports__))[i];
    }
};
pub const HBAPort = extern struct {
    clb: u32,
    clbu: u32,
    fb: u32,
    fbu: u32,
    is: u32,
    ie: u32,
    cmd: u32,
    _reserved_0: u32,
    tfd: u32,
    sig: u32,
    ssts: u32,
    sctl: u32,
    serr: u32,
    sact: u32,
    ci: u32,
    sntf: u32,
    fbs: u32,
    _reserved_1: [11]u32,
    vendor: [4]u32,
};
pub const HBA_FIS = extern struct {
    dsfis: FISDMASetup,
    _padding_0: u32,

    psfis: FISPIOSetup,
    _padding_1: [4]u8,

    rfis: FIS_Reg_D2H,
    _padding_2: [4]u8,

    // wtf is FIS_DEV_BITS???
    sdbfis: u8,

    ufis: [64]u8,

    _reserved_0: [96]u8
};

pub const HBACMDHeader = packed struct {
    cfl: u5,
    a: u1,
    w: u1,
    p: u1,

    r: u1,
    b: u1,
    c: u1,
    _reserved_0: u1,
    pmp: u4,

    prdtl: u16,

    prdbc: u32,

    ctba: u32,
    ctbau: u32,

    _reserved_1: u32,
    _reserved_2: u32,
    _reserved_3: u32,
    _reserved_4: u32,
};
pub const HBACMDTable = extern struct {
    cfis: [64]u8,
    acmd: [16]u8,
    _reserved_0: [48]u8,
    __prdt_entry__: HBAPRDTEntry,

    pub fn prdt_entry(s: *@This(), i: usize) *HBAPRDTEntry {
        return &@as([*]HBAPRDTEntry, @ptrCast(&s.__prdt_entry__))[i];
    }
};
pub const HBAPRDTEntry = packed struct {
    dba: u32,
    dbau: u32,
    _reserved_0: u32 = 0,

    dbc: u22,
    _reserved_1: u9 = 0,
    i: u1
};
