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

extern fn @"Anthragon:buildin_register_capability_callable"(module_uuid: Guid, namespace: [*:0]const u8, symbol: [*:0]const u8, pointer: *const anyopaque) callconv(.c) void;
pub fn buildin_register_capability_callable(namespace: [*:0]const u8, symbol: [*:0]const u8, pointer: *const anyopaque) void {
    switch (module_config.builtin) {
        true => @"Anthragon:buildin_register_capability_callable"(root.module_uuid, namespace, symbol, @ptrCast(pointer)),
        false => {},
    }
}

extern fn @"Anthragon:buildin_register_capability_property"(module_uuid: Guid, namespace: [*:0]const u8, symbol: [*:0]const u8, getter: *const anyopaque, setter: *const anyopaque) callconv(.c) void;
pub fn buildin_register_capability_property(namespace: [*:0]const u8, symbol: [*:0]const u8, getter: *const anyopaque, setter: *const anyopaque) void {
    switch (module_config.builtin) {
        true => @"Anthragon:buildin_register_capability_property"(root.module_uuid, namespace, symbol, @ptrCast(getter), @ptrCast(setter)),
        false => {},
    }
}

extern fn @"Anthragon:buildin_register_capability_event"(module_uuid: Guid, namespace: [*:0]const u8, symbol: [*:0]const u8, bind: *const anyopaque, unbind: *const anyopaque) callconv(.c) void;
pub fn buildin_register_capability_event(namespace: [*:0]const u8, symbol: [*:0]const u8, bind: *const anyopaque, unbind: *const anyopaque) void {
    switch (module_config.builtin) {
        true => @"Anthragon:buildin_register_capability_event"(root.module_uuid, namespace, symbol, @ptrCast(bind), @ptrCast(unbind)),
        false => {},
    }
}
