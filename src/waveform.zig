const std = @import("std");
const math = std.math;
const c = @import("c.zig");

const Streamer = @import("streamer.zig");
const Envelop = @import("envelop.zig");
const Config = @import("config.zig");
const Waveform = @This();

pub const Shape = enum {
    Sine,
    Triangle,
    Sawtooth,
    Square,
    // The family of waveform functions
    // They all have period=1
    pub fn sine_f32(time: f64) f32 {
        return @floatCast(@sin(2 * math.pi * time));
    }

    pub fn triangle_f32(time: f64) f32 {
        const f: f64 = time - @floor(time);
        const r = 2 * @abs(2 * (f - 0.5)) - 1;
        return @floatCast(r);
    }

    pub fn sawtooth_f32(time: f64) f32 {
        const f: f64 = time - @floor(time);
        const r = 2 * (f - 0.5);
        return @floatCast(r);
    }

    pub fn square_f32(time: f64) f32 {
        const f: f64 = time - @floor(time);
        return if (f < 0.5) 1.0 else -1.0;
    }

    pub fn get_wave_func(self: Shape) *const fn (f64) f32 {
        return switch (self) {
            .Sine => sine_f32,
            .Sawtooth => sawtooth_f32,
            .Triangle => triangle_f32,
            .Square => square_f32,
        };
    }
};



pub fn calculate_advance(sample_rate: u32, frequency: f64) f64 {
        return (1.0 / (@as(f64, @floatFromInt(sample_rate)) / frequency));
}

pub const Simple = struct {
    advance: f64,
    time: f64,
    amplitude: f32,
    frequency: f64,
    shape: Shape,

    fn read(ptr: *anyopaque, frames: []f32) struct { u32, Streamer.Status } {
        const self: *Simple = @alignCast(@ptrCast(ptr));
        const func = self.shape.get_wave_func();
        for (0..frames.len) |i| {
            self.time += self.advance;
            frames[i] = func(self.time) * self.amplitude;
        }
        return .{ @intCast(frames.len), Streamer.Status.Continue };
    }

    fn reset(ptr: *anyopaque) bool {
        const self: *Simple = @alignCast(@ptrCast(ptr));
        self.time = 0;
        return true;
    }

    pub fn streamer(self: *Simple) Streamer {
        return .{
            .ptr = @ptrCast(self),
            .vtable = .{
                .read = read,
                .reset = reset,
            },
        };
    }

    pub fn init(amp: f32, freq: f64, shape: Shape) Simple {
        return .{
            .amplitude = amp,
            .frequency = freq,
            .advance = calculate_advance(Config.SAMPLE_RATE, freq),
            .time    = 0,
            .shape = shape,
        };
    }
};
pub const FreqEnvelop = struct {
    time: f64, // time in secs, different from the `time` above
    wave_time: f64,
    amplitude: f32,
    le: Envelop.LinearEnvelop(f64, f64),
    shape: Shape,

    fn read(ptr: *anyopaque, frames: []f32) struct { u32, Streamer.Status } {
        const self: *FreqEnvelop = @alignCast(@ptrCast(ptr));
        const func = self.shape.get_wave_func();
        for (0..frames.len) |i| {
            self.time += 1.0/@as(comptime_float, @floatFromInt(Config.SAMPLE_RATE));
            const freq, const status = self.le.get(self.time);
            self.wave_time += calculate_advance(Config.SAMPLE_RATE, freq);
            frames[i] = func(self.wave_time) * self.amplitude;
            if (status == .Stop) {
                return .{ @intCast(i), .Stop };
            }
        } else {
            return .{ @intCast(frames.len), Streamer.Status.Continue };
        }
    }

    fn reset(ptr: *anyopaque) bool {
        const self: *FreqEnvelop = @alignCast(@ptrCast(ptr));
        self.time = 0;
        self.wave_time = 0;
        return true;
    }

    pub fn streamer(self: *FreqEnvelop) Streamer {
        return .{
            .ptr = @ptrCast(self),
            .vtable = .{
                .read = read,
                .reset = reset,
            },
        };
    }

    pub fn init(amp: f32, freq_le: Envelop.LinearEnvelop(f64, f64), shape: Shape) FreqEnvelop {
        return .{
            .time = 0,
            .wave_time = 0,
            .amplitude = amp,
            .le = freq_le,
            .shape = shape,
        };
    }
};

pub const WhiteNoise = struct {
    amp: f32,
    random: std.Random,

    pub fn streamer(self: *WhiteNoise) Streamer {
        return .{
            .ptr = @ptrCast(self),
            .vtable = .{
                .read = read_impl,
                .reset = reset,
            },
        };
    }

   fn read(self: *WhiteNoise, frames: []f32) struct { u32, Streamer.Status } {
        for (0..frames.len) |i| {
            frames[i] = 2*(self.random.float(f32)-0.5) * self.amp;
        }
        return .{ @intCast(frames.len), .Continue };
    }
   fn read_impl(ptr: *anyopaque, frames: []f32) struct { u32, Streamer.Status } {
        const self: *WhiteNoise = @alignCast(@ptrCast(ptr));
        return self.read(frames);
    }

   fn reset(ptr: *anyopaque) bool { 
       _ = ptr; 
       return true;
   }
};

pub const BrownNoise = struct {
    white: WhiteNoise,
    rc: f32,
    pub fn streamer(self: *BrownNoise) Streamer {
        return .{
            .ptr = @ptrCast(self),
            .vtable = .{
                .read = read,
                .reset = reset,
            },
        };
    }

   fn read(ptr: *anyopaque, frames: []f32) struct { u32, Streamer.Status } {
        const self: *BrownNoise = @alignCast(@ptrCast(ptr));
        var tmp = [_]f32 {0} ** 4096;
        _ = self.white.read(&tmp);
        const dt: f32 = @as(f32, @floatFromInt(frames.len)) / Config.SAMPLE_RATE;
        const a: f32 = dt / (self.rc + dt);
        frames[0] = a * tmp[0];
        for (1..frames.len) |i| {
            frames[i] = a * tmp[i] + (1-a) * frames[i-1];
        }
        return .{ @intCast(frames.len), .Continue };
    }

   fn reset(ptr: *anyopaque) bool { 
       _ = ptr; 
       return true;
   }
};

pub const StringNoise = struct {
    buf: [1024]f32,
    count: u32,
    buf_len: u32,

    feedback: f32,
    stop_feedback: f32,
    amp: f32,

    random: std.Random,
    
    stopped: bool = false,
    pub fn init(amp: f32, freq: f64, random: std.Random) StringNoise {
        var sn = StringNoise {
            .count = 0,
            .buf_len = @intFromFloat(Config.SAMPLE_RATE / freq),
            .feedback = 0.99996,                       
            .stop_feedback = 0.6,
            .buf = undefined,
            .amp = amp,
            .random = random
        };
        std.debug.assert(sn.buf_len <= 1024);
        for (0..sn.buf_len) |i| {
            // fit a single cycle into the buffer
            // var t: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(sn.buf_len));
            // string->buf[i] = ma_waveform_square_f32(t, 1);
            // string->buf[i] = ma_waveform_sawtooth_f32(t, 1);
            sn.buf[i] = (sn.random.float(f32) - 0.5) * 2;
        }
        return sn;
    }

    fn read(ptr: *anyopaque, frames: []f32) struct { u32, Streamer.Status } {
        const self: *StringNoise = @alignCast(@ptrCast(ptr));
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
            self.buf[self.count] = sum / (range * 2 + 1) * if (self.stopped) self.stop_feedback else self.feedback;
            self.count = (self.count + 1) % self.buf_len;
        }
        return .{ @intCast(frames.len), .Continue };
    }

    fn reset(ptr: *anyopaque) bool {
        const self: *StringNoise = @alignCast(@ptrCast(ptr));
        for (0..self.buf_len) |i| {
            self.buf[i] = (self.random.float(f32) - 0.5) * 2;
        }
        self.stopped = false;
        self.count = 0;
        return true;
    }

    fn stop(ptr: *anyopaque) bool {
        const self: *StringNoise = @alignCast(@ptrCast(ptr));
        self.stopped = true;
        return true;
    }

    pub fn streamer(self: *StringNoise) Streamer {
        return .{
            .ptr = @ptrCast(self),
            .vtable = .{
                .read = read,
                .reset = reset,
                .stop = stop,
            }
        };
    }

};
