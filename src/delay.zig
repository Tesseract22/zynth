const std = @import("std");
const Streamer = @import("streamer.zig");
const Config = @import("config.zig");
const RingBuffer =  @import("ring_buffer.zig");

const MAX_BUF_LEN = Config.SAMPLE_RATE;
const DelayBuf = RingBuffer.FixedRingBuffer(f32, MAX_BUF_LEN);
pub const Delay = struct {
    sub_streamer: Streamer,
    buf: DelayBuf,
    playback: f32,
    rest: u32,
    pub fn initSample(sub_streamer: Streamer, delay_sample: u32, playback: f32) Delay {
        return Delay {
            .sub_streamer = sub_streamer,
            .buf = DelayBuf.init(delay_sample),
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
        const len: u32 = @intCast(@min(out.len, self.buf.len-self.rest));
        for (0..len) |i| {
            if (self.buf.is_full()) {
                out[i] += self.buf.at(0) * self.playback;
            }
            self.buf.push(out[i]);
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
    var rand = std.Random.Xoroshiro128.init(0);
    var random = rand.random();
    const DelayLines = 10;
    sub_streamer: Streamer,
    bufs: [DelayLines]DelayBuf,
    playback: f32,
    rest: u32,
    pub fn initSample(sub_streamer: Streamer, delay_sample: [DelayLines]u32, playback: f32) Reverb {
        var res = Reverb {
            .sub_streamer = sub_streamer,
            .bufs = undefined,
            .playback = playback,
            .rest = 0,
        };
        for (0..DelayLines) |i| {
            res.bufs[i] = DelayBuf.init(delay_sample[i]);
        }
        return res;
    }

    pub fn initSecs(sub_streamer: Streamer, delay_secs: [DelayLines]f32, playback: f32) Reverb {
        var delay_samples: [DelayLines]u32 = undefined;
        for (0..DelayLines) |i| {
            delay_samples[i] = @intFromFloat(delay_secs[i] * Config.SAMPLE_RATE);
        }
        return initSample(sub_streamer, delay_samples, playback);
    }

    pub fn initRandomize(sub_streamer: Streamer, sec: f32, randomness: f32, playback: f32) Reverb {
        var delay_secs: [DelayLines]f32 = undefined;
        for (0..DelayLines) |i| {
            delay_secs[i] = sec + 2*(random.float(f32)-0.5) * randomness * sec;
        }
        return initSecs(sub_streamer, delay_secs, playback);
    }
    fn read(ptr: *anyopaque, out: []f32) struct { u32, Streamer.Status } {
        const self: *Reverb = @alignCast(@ptrCast(ptr));
        _ = self.sub_streamer.read(out);
        // With this method, the output of the previous (lower index) delay line feeds into the next one (higher index).
        // TODO: create a matrix to represent the feeding relationship between delay lines.
        for (&self.bufs) |*buf| {
            for (0..out.len) |i| {
                if (buf.is_full()) {
                    out[i] += buf.at(0) * self.playback;
                }
                buf.push(out[i]);
            }
        }
        return .{ @intCast(out.len), .Continue };
    }

    fn reset(ptr: *anyopaque) bool {
        const self: *Reverb = @alignCast(@ptrCast(ptr));
        for (&self.bufs) |*buf| {
            buf.clear(0);
        }
        return self.sub_streamer.reset();
    }

    pub fn streamer(self: *Reverb) Streamer {
        return .{
            .ptr = @ptrCast(self),
            .vtable = .{
                .read = read,
                .reset = reset,
            }
        };
    }
};
