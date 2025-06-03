const std = @import("std");
const Config = @import("config.zig");
const Streamer = @import("streamer.zig");
var rand = std.Random.Xoroshiro128.init(0);
pub const StringNoise = struct {
    buf: [1024]f32,
    count: u32,
    buf_len: u32,
    feedback: f32,
    amp: f32,
    pub fn init(freq: f64, amp: f32) StringNoise {
        var sn = StringNoise {
            .count = 0,
            .buf_len = @intFromFloat(Config.SAMPLE_RATE / freq),
            .feedback = 0.996,                       
            .buf = undefined,
            .amp = amp,
        };
        std.debug.assert(sn.buf_len <= 1024);
        for (0..sn.buf_len) |i| {
            // fit a single cycle into the buffer
            // var t: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(sn.buf_len));
            // string->buf[i] = ma_waveform_square_f32(t, 1);
            // string->buf[i] = ma_waveform_sawtooth_f32(t, 1);
            sn.buf[i] = (rand.random().float(f32) - 0.5) * 2;
        }
        return sn;
    }

    fn read(ptr: *anyopaque, frames: []f32) void {
        const self: *StringNoise = @ptrCast(ptr);
        const feedback_decay = 1;
        const feedback: f32 = self.feedback * feedback_decay;
        for (0..frames.len) |frame_i| {
            for (0..Config.CHANNELS) |channel_i| {
                frames[frame_i * Config.CHANNELS + channel_i] = self.buf[self.count] * self.amp;
            }
            const range = 1;
            var sum: f32 = 0;
            const len: i32 = @intCast(self.buf_len);
            var i: i32 = -range;
            while (i <= range) : (i += 1) {
                const idx = @mod(@as(i32, @intCast(self.count)) + i, len);
                sum += self.buf[@intCast(idx)];
            }
            self.buf[self.count] = sum / (range * 2 + 1) * feedback;

            //printf("sum: %f\n", sum);
            self.count = (self.count + 1) % self.buf_len;

        }
    }

    pub fn streamer(self: *StringNoise) Streamer {
        return .{
            .ptr = @ptrCast(self),
            .vtable = .{
                .read = read,
            }
        };
    }
};
