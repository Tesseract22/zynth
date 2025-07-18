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

pub const VTable = struct {
    read: *const fn(self: *anyopaque, frames: []f32) struct { u32, Status },
    reset: *const fn(self: *anyopaque) bool,
    stop: *const fn(self: *anyopaque) bool = stop_noop,


    pub fn stop_noop(self: *anyopaque) bool { 
        _ = self;
        return false;
    }
};

pub fn read(self: Streamer, frames: []f32) struct { u32, Status } {
    return self.vtable.read(self.ptr, frames);
}

pub fn reset(self: Streamer) bool {
    return self.vtable.reset(self.ptr);
}

pub fn stop(self: Streamer) bool {
    return self.vtable.stop(self.ptr);
} 

