const std = @import("std");
const Streamer = @import("streamer.zig");
const Config = @import("config.zig");
const RingBuffer =  @import("ring_buffer.zig");

const MAX_BUF_LEN = 1024 * 4;
pub const Delay = struct {
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
        const sub_len, _ = self.sub_streamer.read(out);
        const len = @min(out.len, MAX_BUF_LEN-self.rest);
        for (0..len) |i| {
            const tmp = out[i];
            if (self.buf.count == MAX_BUF_LEN) {
                out[i] += self.buf.at(0) * self.playback;
            }
            self.buf.push(tmp);
        }
        self.rest += len - sub_len;
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
};

pub const Reverb = struct {
    sub_streamer: Streamer,
    buf: RingBuffer.FixedRingBuffer(f32, MAX_BUF_LEN),
    delay_sample: u32,
    playback: f32,
    rest: u32,
    pub fn initSample(sub_streamer: Streamer, delay_sample: u32, playback: f32) Reverb {
        std.debug.assert(delay_sample <= MAX_BUF_LEN);
        return .{
            .sub_streamer = sub_streamer,
            .buf = .{},
            .delay_sample = delay_sample,
            .playback = playback,
            .rest = 0,
        };
    }

    pub fn initSecs(sub_streamer: Streamer, delay_secs: f32, playback: f32) Reverb {
        return initSample(sub_streamer, delay_secs / Config.SAMPLE_RATE, playback);
    }

    fn read(ptr: *anyopaque, out: []f32) struct { u32, Streamer.Status } {
        const self: *Delay = @alignCast(@ptrCast(ptr));
        _, _ = self.sub_streamer.read(out);
        const len = out.len;
        for (0..len) |i| {
            if (self.buf.count == MAX_BUF_LEN) {
                out[i] += self.buf.at(0) * self.playback;
            }
            self.buf.push(out[i]);
        }
        // self.rest += len - sub_len;
        // if (self.rest >= MAX_BUF_LEN) return .{ @intCast(out.len), .Stop };
        return .{ @intCast(out.len), .Continue };
    }

    pub fn streamer(self: *Reverb) Streamer {
        return .{
            .ptr = @ptrCast(self),
            .vtable = .{
                .read = read,
            }
        };
    }
};
