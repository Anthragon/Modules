const std = @import("std");
const root = @import("root.zig");
const Guid = root.utils.Guid;
const interop = root.interop;
const Result = interop.Result;

pub fn get_node(path: [:0]const u8) !*Node {
    return root.vtable.v1.capabilities_getNode(path.ptr) orelse error.NotFound;
}
pub fn create_resource(parent: *Node, name: [:0]const u8) !*Node {
    return root.vtable.v1.capabilities_createResource(parent, name.ptr) orelse error.NotCreated;
}
pub fn create_callable(parent: *Node, name: [:0]const u8, callable: *const anyopaque) !*Node {
    return root.vtable.v1.capabilities_createCallable(parent, name.ptr, callable).asbuiltin();
}
pub fn create_property(parent: *Node, name: [:0]const u8, getter: *const anyopaque, setter: *const anyopaque) !*Node {
    return root.vtable.v1.capabilities_createProperty(parent, name.ptr, getter, setter).asbuiltin();
}
pub fn create_event(parent: ?*Node, name: [:0]const u8, bind: *const anyopaque, unbind: *const anyopaque) !*Node {
    return root.vtable.v1.capabilities_createEvent(parent, name.ptr, bind, unbind).asbuiltin();
}

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
