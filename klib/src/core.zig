const root = @import("root.zig");
const kernel = @import("kernel");
const module_config = @import("module_config");
const Guid = root.Guid;

const PanicSig = *const fn (module_uuid: Guid, message: [*:0]const u8) callconv(.c) noreturn;
pub const panic: PanicSig = switch (module_config.builtin) {
    true => @extern(PanicSig, .{ .name = "cap privileged_callable [00000000-0000-0000-0000-000000000000]System.ModuleHelper::panic" }),
    false => @extern(PanicSig, .{ .name = "cap callable [00000000-0000-0000-0000-000000000000]System.ModuleHelper::panic" }),
};

const LogSig = *const fn (module_uuid: Guid, scope: [*:0]const u8, message: [*:0]const u8) callconv(.c) void;
pub const log_info: LogSig = switch (module_config.builtin) {
    true => @extern(LogSig, .{ .name = "cap privileged_callable [00000000-0000-0000-0000-000000000000]System.ModuleHelper::log_info" }),
    false => @extern(LogSig, .{ .name = "cap callable [00000000-0000-0000-0000-000000000000]System.ModuleHelper::log_info" }),
};
pub const log_debug: LogSig = switch (module_config.builtin) {
    true => @extern(LogSig, .{ .name = "cap privileged_callable [00000000-0000-0000-0000-000000000000]System.ModuleHelper::log_debug" }),
    false => @extern(LogSig, .{ .name = "cap callable [00000000-0000-0000-0000-000000000000]System.ModuleHelper::log_debug" }),
};
pub const log_warn: LogSig = switch (module_config.builtin) {
    true => @extern(LogSig, .{ .name = "cap privileged_callable [00000000-0000-0000-0000-000000000000]System.ModuleHelper::log_warn" }),
    false => @extern(LogSig, .{ .name = "cap callable [00000000-0000-0000-0000-000000000000]System.ModuleHelper::log_warn" }),
};
pub const log_err: LogSig = switch (module_config.builtin) {
    true => @extern(LogSig, .{ .name = "cap privileged_callable [00000000-0000-0000-0000-000000000000]System.ModuleHelper::log_err" }),
    false => @extern(LogSig, .{ .name = "cap callable [00000000-0000-0000-0000-000000000000]System.ModuleHelper::log_err" }),
};

extern fn @"Anthragon:buildin_register_capability"(
    module_uuid: Guid,
    kind: kernel.CapabilityKind,
    namespace: [*:0]const u8,
    symbol: [*:0]const u8,
    pointer: *const anyopaque,
) callconv(.c) void;
pub fn buildin_register_capability(
    kind: kernel.CapabilityKind,
    namespace: [*:0]const u8,
    symbol: [*:0]const u8,
    pointer: *const anyopaque,
) void {
    switch (module_config.builtin) {
        true => {
            @"Anthragon:buildin_register_capability"(
                root.module_uuid,
                kind,
                namespace,
                symbol,
                @ptrCast(pointer),
            );
        },
        false => {},
    }
}
