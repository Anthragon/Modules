const std = @import("std");
const root = @import("root");
const main = @import("main.zig");
const debug = root.debug;
const mem = root.mem;
const dev = root.devices;
const disk = dev.disk;

const allocator = mem.heap.kernel_buddy_allocator;

const HBAMem = main.HBAMem;
const HBAPort = main.HBAPort;
const HBACMDHeader = main.HBACMDHeader;
const HBACMDTable = main.HBACMDTable;
const HBAPRDTEntry = main.HBAPRDTEntry;
const FIS_Reg_H2D = main.FIS_Reg_H2D;

const DiskEntryContext = struct {
    abar: *HBAMem,
    port: *HBAPort,
    lba48: bool,
    sec_size: usize
};

const find_cmdslot = main.find_cmdslot;

pub fn init_disk(abar: *HBAMem, port: *HBAPort) !void {

    debug.err("Initializing disk...\n", .{});

    stop_cmd(port);
    start_cmd(port);

    const identify = try identify_sata(abar, port);

    const lba48_supported = (identify.command_set_2 & (1 << 10)) != 0;
    const rotation_rate = identify.rotation_rate;
    const total_sectors: u64 = if (lba48_supported) (@as(u64, identify.total_usr_sectors[1]) << 32) | @as(u64, identify.total_usr_sectors[0]) else identify.lba_capacity;
    const sector_size = if (identify.words_per_sector == 0) 512 else identify.words_per_sector * 2;

    // The total of virtual sectors (sectors of exactly 512 bytes)
    const total_vsectors = total_sectors * @divExact(sector_size, 512);

    const ctx = allocator.create(DiskEntryContext) catch unreachable;
    ctx.* = .{
        .abar = abar,
        .port = port,

        .lba48 = lba48_supported,
        .sec_size = sector_size,

    };
    _ = dev.disk.append_device(
        ctx,
        if (rotation_rate == 0) @as([]const u8, "SATA-SSD") else @as([]const u8, "SATA-HDD"),
        total_vsectors,
        &sata_vtable
    );
    
}

pub fn identify_sata(abar: *HBAMem, port: *HBAPort) !IdentifyDeviceData {
   
   var buf: [512]u8 = undefined;

    port.is = @bitCast(@as(i32, -1));
    const i_slot = find_cmdslot(port, ((abar.cap >> 8) & 0x1F) + 1);
    if (i_slot == -1) return error.NoCmdSlot;
    const slot: usize = @intCast(i_slot);

    const cmdheaders = mem.ptrFromPhys([*]HBACMDHeader,
        (@as(u64, @intCast(port.clbu)) << 32) | @as(u64, @intCast(port.clb)));
    const cmdheader = &cmdheaders[slot];
    cmdheader.cfl = @sizeOf(FIS_Reg_H2D) / @sizeOf(u32);
    cmdheader.w = 0;
    cmdheader.prdtl = 1;

    const cmdtbl = mem.ptrFromPhys(*HBACMDTable,
        (@as(u64, @intCast(cmdheader.ctbau)) << 32) | @as(u64, @intCast(cmdheader.ctba)));
    @memset(@as([*]u8, @ptrCast(cmdtbl))[0 .. @sizeOf(HBACMDTable) + @sizeOf(HBAPRDTEntry)], 0);

    const phys_buf = mem.physFromPtr((&buf).ptr);
    cmdtbl.prdt_entry(0).* = .{
        .dba  = @intCast(phys_buf & 0xFFFFFFFF),
        .dbau = @intCast(phys_buf >> 32),
        .dbc  = 512 - 1,
        .i    = 1
    };

    const fis: *FIS_Reg_H2D = @ptrCast(&cmdtbl.cfis);
    fis.* = .{
        .fis_type = 0x27,
        .pmport   = 0,
        .c        = 1,
        .command  = 0xEC,
        .featurel = 0,
        .featureh = 0,
        .lba0 = 0, .lba1 = 0, .lba2 = 0,
        .device = 0,
        .lba3 = 0, .lba4 = 0, .lba5 = 0,
        .countl = 0, .counth = 0,
        .icc = 0, .control = 0,
    };

    var spin: usize = 0;
    while ((port.tfd & 0x88) != 0 and spin < 1000000) : (spin += 1) {}
    if (spin == 1000000) return error.PortIsHung;

    port.ci = std.math.shl(u32, 1, slot);

    var timeout: usize = 0;
    while (true) : (timeout += 1) {
        if ((port.ci & std.math.shl(u32, 1, slot)) == 0) break;
        if ((port.is & (1 << 30)) != 0) return error.ReadError;
        if (timeout > 100000) return error.Timeout;
    }

    return std.mem.bytesToValue(IdentifyDeviceData, &buf);
}

const sata_vtable: disk.DiskEntry.VTable = .{
    .read = read_sata,
    .write = write_sata,
    .remove = remove
};

// Hooks
fn read_sata(ctx: *anyopaque, sector: u64, buffer: [*]u8, len: usize) callconv(.c) bool {

    if (len % 512 != 0) return false;

    const context: *DiskEntryContext = @ptrCast(@alignCast(ctx));
    const abar = context.abar;
    const port = context.port;
    var buf = buffer[0 .. len];

    port.is = @bitCast(@as(i32, -1));
    const i_slot = find_cmdslot(port, ((abar.cap >> 8) & 0x1F) + 1);

    if (i_slot == -1) return false;
    const slot: usize = @bitCast(i_slot);

    const cmdheader_list = mem.ptrFromPhys([*]HBACMDHeader, @as(u64, @intCast(port.clbu)) << 32 | @as(u64, @intCast(port.clb)));
    const cmdheader = &cmdheader_list[slot];
    cmdheader.cfl = @sizeOf(FIS_Reg_H2D) / @sizeOf(u32);

    cmdheader.w = 0;
    cmdheader.prdtl = @truncate(std.math.divCeil(usize, buf.len, 0x4000) catch unreachable);

    const cmdtbl = mem.ptrFromPhys(*HBACMDTable, @as(u64, @intCast(cmdheader.ctbau)) << 32 | @as(u64, @intCast(cmdheader.ctba)));
    const total_prdt_size = @sizeOf(HBACMDTable) + (cmdheader.prdtl - 1) * @sizeOf(HBAPRDTEntry);
    @memset(@as([*]u8, @ptrCast(cmdtbl))[0..total_prdt_size], 0);

    for (0 .. cmdheader.prdtl - 1) |i| {
        const phys_buf = mem.physFromPtr(buf.ptr);
        cmdtbl.prdt_entry(i).dba =  @intCast(phys_buf & 0xFFFFFFFF);
        cmdtbl.prdt_entry(i).dbau = @intCast(phys_buf >> 32);
        cmdtbl.prdt_entry(i).i = 1;
        buf = buf[4096 ..];
    }

    const phys_buf = mem.physFromPtr(buf.ptr);
    cmdtbl.prdt_entry(cmdheader.prdtl - 1).dba =  @truncate(phys_buf & 0xFFFFFFFF);
    cmdtbl.prdt_entry(cmdheader.prdtl - 1).dbau = @truncate(phys_buf >> 32);
    cmdtbl.prdt_entry(cmdheader.prdtl - 1).dbc = @truncate(buf.len - 1);
    cmdtbl.prdt_entry(cmdheader.prdtl - 1).i = 1;

    const cmdfis: *FIS_Reg_H2D = @ptrCast(&cmdtbl.cfis);

    cmdfis.fis_type = 0x27;
    cmdfis.c = 1;
    cmdfis.command = 0x25;

    cmdfis.lba0 = @truncate((sector >> 0) & 0xFF);
    cmdfis.lba1 = @truncate((sector >> 8) & 0xFF);
    cmdfis.lba2 = @truncate((sector >> 16) & 0xFF);
    cmdfis.lba3 = @truncate((sector >> 24) & 0xFF);
    cmdfis.lba4 = @truncate((sector >> 32) & 0xFF);
    cmdfis.lba5 = @truncate((sector >> 40) & 0xFF);

    cmdfis.device = 1 << 6;
    const sector_count = @divExact(buf.len, 512);
    cmdfis.countl = @truncate(sector_count & 0xFF);
    cmdfis.counth = @truncate((sector_count >> 8) * 0xFF);

    var spin: usize = 0;
    while ((port.tfd & (0x88) != 0) and spin < 1000000) : (spin += 1) {}

    if (spin == 1000000) {
        debug.err("Port is hung\n", .{});
        return false;
    }

    port.ci = std.math.shl(u32, 1, slot);

    var timeout: usize = 0;
    while (true) : (timeout += 1) {
        if ((port.ci & std.math.shl(u32, 1, slot)) == 0) break;

        if (timeout >= (1 << 16)) {
            debug.err("Timeout\n", .{});
            return false;
        }
        if ((port.is & (1 << 30)) != 0) {
           debug.err("Read disk error\n", .{});
           return false;
        }
    }

    return true;
}
fn write_sata(ctx: *anyopaque, sector: u64, buffer: [*]u8, len: usize) callconv(.c) bool {
    _ = ctx;
    _ = sector;
    _ = buffer;
    _ = len;
    return false;
}
fn remove(ctx: *anyopaque) callconv(.c) void {
    const context: *DiskEntryContext = @ptrCast(@alignCast(ctx));
    allocator.destroy(context);
}

fn start_cmd(port: *HBAPort) void {
    while (port.cmd & 0x8000 != 0) {}
    port.cmd |= 0x0010;
    port.cmd |= 0x0001;
}
fn stop_cmd(port: *HBAPort) void {
    port.cmd &= ~@as(u32, 0x0001);
    port.cmd &= ~@as(u32, 0x0010);

    while (true) {
        if (port.cmd & 0x4000 != 0) continue;
        if (port.cmd & 0x8000 != 0) continue;
        break;
    }
}

// This struct is massively huge bruh
pub const IdentifyDeviceData = extern struct {
    config: u16,
    cyls: u16,
    reserved2: u16,
    heads: u16,
    track_bytes: u16,
    sector_bytes: u16,
    sectors: u16,
    vendor0: u16,
    vendor1: u16,
    vendor2: u16,
    serial_no: [20]u8,
    buf_type: u16,
    buf_size: u16,
    ecc_bytes: u16,
    fw_rev: [8]u8,
    model: [40]u8,
    multi_count: u16,
    dword_io: u16,
    capability1: u16,
    capability2: u16,
    vendor5: u8,
    tPIO: u8,
    vendor6: u8,
    tDMA: u8,
    field_valid: u16,
    cur_cyls: u16,
    cur_heads: u16,
    cur_sectors: u16,
    cur_capacity0: u16,
    cur_capacity1: u16,
    multsect: u8,
    multsect_valid: u8,
    lba_capacity: u32,
    dma_1word: u16,
    dma_mword: u16,
    eide_pio_modes: u16,
    eide_dma_min: u16,
    eide_dma_time: u16,
    eide_pio: u16,
    eide_pio_iordy: u16,
    words69_70: [2]u16,
    words71_74: [4]u16,
    queue_depth: u16,
    sata_capability: u16,
    sata_additional: u16,
    sata_supported: u16,
    features_enabled: u16,
    major_rev_num: u16,
    minor_rev_num: u16,
    command_set_1: u16,
    command_set_2: u16,
    cfsse: u16,
    cfs_enable_1: u16,
    cfs_enable_2: u16,
    csf_default: u16,
    dma_ultra: u16,
    word89: u16,
    word90: u16,
    CurAPMvalues: u16,
    word92: u16,
    comreset: u16,
    accoustic: u16,
    min_req_sz: u16,
    transfer_time_dma: u16,
    access_latency: u16,
    perf_granularity: u32,
    total_usr_sectors: [2]u32,
    transfer_time_pio: u16,
    reserved105: u16,
    sector_sz: u16,
    inter_seek_delay: u16,
    words108_116: [9]u16,
    words_per_sector: u32,
    supported_settings: u16,
    command_set_3: u16,
    words121_126: [6]u16,
    word127: u16,
    security_status: u16,
    csfo: u16,
    words130_155: [26]u16,
    word156: u16,
    words157_159: [3]u16,
    cfa: u16,
    words161_175: [15]u16,
    media_serial: [60]u8,
    sct_cmd_transport: u16,
    words207_208: [2]u16,
    block_align: u16,
    WRV_sec_count: u32,
    verf_sec_count: u32,
    nv_cache_capability: u16,
    nv_cache_sz: u16,
    nv_cache_sz2: u16,
    rotation_rate: u16,
    reserved218: u16,
    nv_cache_options: u16,
    words220_221: [2]u16,
    transport_major_rev: u16,
    transport_minor_rev: u16,
    words224_233: [10]u16,
    min_dwnload_blocks: u16,
    max_dwnload_blocks: u16,
    words236_254: [19]u16,
    integrity: u16,
};
