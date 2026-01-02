const std = @import("std");
const root = @import("root");
const Guid = root.utils.Guid;
const interop = root.interop;
const Result = interop.Result;

const NodeDataTags = enum {
    resource,
    field,
    callable,
    event,
};
pub const Node = struct {
    parent: ?*Node,
    name: [:0]const u8,
    global: [:0]const u8,

    data: union(NodeDataTags) {
        resource: Resource,
        field: Field,
        callable: Callable,
        event: Event,
    },
};

const Resource = struct {
    children: std.StringArrayHashMapUnmanaged(*Node),
};

const Field = *anyopaque;

const Callable = *const anyopaque;

const Event = extern struct {
    pub const EventOnBindCallback = *const fn (*const anyopaque, ?*anyopaque) callconv(.c) bool;
    pub const EventOnUnbindCallback = *const fn (*const anyopaque) callconv(.c) void;

    bind_callback: EventOnBindCallback,
    unbind_callback: EventOnUnbindCallback,

    pub fn bind(s: @This(), func: *const anyopaque, ctx: ?*anyopaque) callconv(.c) bool {
        return s.bind_callback(func, ctx);
    }
    pub fn unbind(s: @This(), func: *const anyopaque) callconv(.c) void {
        s.unbind_callback(func);
    }
};
