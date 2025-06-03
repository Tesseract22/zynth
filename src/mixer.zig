const std = @import("std");
const Waveform = @import("waveform.zig");
const Streamer = @import("streamer.zig");
const RingBuffer = @import("ring_buffer.zig");
const Tone = Waveform.Tone;
const Envelop = Waveform.Envelop;
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

pub fn read(ptr: *anyopaque, float_out: []f32) Streamer.Status {
    const self: *Mixer = @alignCast(@ptrCast(ptr));
    var tmp = [_]f32 {0} ** 4096;
    for (0..self.streams.count) |i| {
        if (!self.streams.active.isSet(@intCast(i))) continue;
        const status = self.streams.at(@intCast(i)).read(tmp[0..float_out.len]);
        for (0..float_out.len) |frame_i|
            float_out[frame_i] += tmp[frame_i];
        if (status == .Stop) self.streams.remove(@intCast(i));
    }
    return Streamer.Status.Continue;
}

pub fn streamer(self: *Mixer) Streamer {
    return .{
        .ptr = @ptrCast(self),
        .vtable = .{
            .read = read,
        }
    };
}
