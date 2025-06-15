const std = @import("std");
const Waveform = @import("waveform.zig");
const Streamer = @import("streamer.zig");
const RingBuffer = @import("ring_buffer.zig");
const c = @import("c.zig");
const Mixer = @This();
pub const POOL_LEN = 32;

streams: RingBuffer.FixedRingBuffer(Streamer, POOL_LEN) = .{},
    
pub const KeyNote = struct {
    key: u8,
    note: i32,
};

pub fn play(self: *Mixer, stream: Streamer) void {
    self.streams.push(stream);
}

fn read(ptr: *anyopaque, float_out: []f32) struct { u32, Streamer.Status } {
    const self: *Mixer = @alignCast(@ptrCast(ptr));
    var max_len: u32 = 0;
    for (0..self.streams.data.len) |i| {
        var tmp = [_]f32 {0} ** 4096;
        if (!self.streams.active.isSet(@intCast(i))) continue;
        const len, const status = self.streams.data[i].read(tmp[0..float_out.len]);
        for (0..len) |frame_i|
            float_out[frame_i] += tmp[frame_i];
        max_len = @max(max_len, len);
        _ = status;
        // if (status == .Stop) self.streams.remove(@intCast(i));
    }
    return .{ max_len, Streamer.Status.Continue };
}

fn reset(ptr: *anyopaque) bool {
    const self: *Mixer = @alignCast(@ptrCast(ptr));
    var success = true;
    for (&self.streams.data, 0..) |*stream, i| {
        if (!self.streams.active.isSet(@intCast(i))) continue;
        success = stream.reset() and success;
    }
    return success;
}

pub fn streamer(self: *Mixer) Streamer {
    return .{
        .ptr = @ptrCast(self),
        .vtable = .{
            .read = read,
            .reset = reset,
        }
    };
}
