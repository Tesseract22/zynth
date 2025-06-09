const std = @import("std");
const Streamer = @import("streamer.zig");
const Config = @import("config.zig");
const RingBuffer =  @import("ring_buffer.zig");
const Delay = @This();

const MAX_BUF_LEN = 1024 * 4;

sub_streamer: Streamer,
buf: RingBuffer.FixedRingBuffer(f32, MAX_BUF_LEN),
delay_sample: u32,
playback: f32,
rest: u32,
pub fn initSample(sub_streamer: Streamer, delay_sample: u32, playback: f32) Delay {
    std.debug.assert(delay_sample <= MAX_BUF_LEN);
    return .{
        .sub_streamer = sub_streamer,
        .buf = .{},
        .delay_sample = delay_sample,
        .playback = playback,
        .rest = 0,
    };
}

pub fn initSecs(sub_streamer: Streamer, delay_secs: f32, playback: f32) Delay {
    return initSample(sub_streamer, delay_secs / Config.SAMPLE_RATE, playback);
}

fn read(ptr: *anyopaque, out: []f32) struct { u32, Streamer.Status } {
    const self: *Delay = @alignCast(@ptrCast(ptr));
    const len, const status = self.sub_streamer.read(out);
    if (status == .Stop) return .{len, .Stop};
    // std.log.debug("len {} {}", .{out.len, MAX_BUF_LEN});
    for (0..out.len) |i| {
        const tmp =if (i < len) out[i] else 0;
        if (self.buf.count == MAX_BUF_LEN) {
            out[i] += self.buf.at(0) * self.playback;
        }
        self.buf.push(tmp);
    }
    if (status == .Stop) self.rest += @intCast(out.len);
    if (self.rest >= MAX_BUF_LEN) return .{ @intCast(out.len), .Stop };
    return .{ @intCast(out.len), .Continue };
}

pub fn streamer(self: *Delay) Streamer {
    return .{
        .ptr = @ptrCast(self),
        .vtable = .{
            .read = read,
        }
    };
}
