pub const Module = extern struct {
    name: [*:0]const u8,
    version: [*:0]const u8,
    author: [*:0]const u8,
    liscence: [*:0]const u8,
    uuid: u128,
};
