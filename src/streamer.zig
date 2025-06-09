const Streamer = @This();

pub const Status = enum {
    Continue,
    Stop,
};
ptr: *anyopaque,
vtable: VTable,

const VTable = struct {
    read: *const fn(self: *anyopaque, frames: []f32) struct { u32, Status },
};

pub fn read(self: Streamer, frames: []f32) struct { u32, Status } {
    return self.vtable.read(self.ptr, frames);

}
