const std = @import("std");

export const module_info_impl linksection(".kernel_modules") = Module{
    .name = "linkageTest",
    .version = "0.1.0",
    .author = "lumi2021",
    .license = "MPL-2.0",
    .uuid = 0,
    .init = &init,
    .deinit = &deinit,
};

fn init() callconv(.c) bool {
    _ = module_info_impl;
    return true;
}
fn deinit() callconv(.c) void {}

const Module = extern struct {
    name: [*:0]const u8,
    version: [*:0]const u8,
    author: [*:0]const u8,
    license: [*:0]const u8,
    uuid: u128,

    init: *const fn () callconv(.c) bool,
    deinit: *const fn () callconv(.c) void,
};
