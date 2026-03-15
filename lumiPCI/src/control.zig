const root = @import("main.zig");
const klib = @import("klib");
const Result = klib.Result;

pub fn control(device: *anyopaque, ctlPtr: [*]usize, ctlLen: usize) callconv(.c) Result(usize) {
    _ = device;
    _ = ctlPtr;
    _ = ctlLen;
    return .err(.notImplemented);
}
