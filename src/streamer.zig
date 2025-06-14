const Streamer = @This();

pub const Status = enum(u8) {
    Stop = 0,
    Continue = 1,
    pub fn andStatus(self: Status, other: Status) Status {
        return @enumFromInt(@intFromEnum(self) & @intFromEnum(other));
    }
};
ptr: *anyopaque,
vtable: VTable,

const VTable = struct {
    read: *const fn(self: *anyopaque, frames: []f32) struct { u32, Status },
    reset: *const fn(self: *anyopaque) bool,
};

pub fn read(self: Streamer, frames: []f32) struct { u32, Status } {
    return self.vtable.read(self.ptr, frames);
}

pub fn reset(self: Streamer) bool {
    return self.vtable.reset(self.ptr);
}
