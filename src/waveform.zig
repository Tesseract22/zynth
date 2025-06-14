const std = @import("std");
const c = @import("c.zig");

const Streamer = @import("streamer.zig");
const Envelop = @import("envelop.zig");
const Config = @import("config.zig");
const Waveform = @This();
const math = std.math;

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

pub const Noise = struct {
    amp: f32,
    random: std.Random,

    pub fn streamer(self: *Noise) Streamer {
        return .{
            .ptr = @ptrCast(self),
            .vtable = .{
                .read = read,
                .reset = reset,
            },
        };
    }

   fn read(ptr: *anyopaque, frames: []f32) struct { u32, Streamer.Status } {
        const self: *Noise = @alignCast(@ptrCast(ptr));
        for (0..frames.len) |i| {
            frames[i] = 2*(self.random.float(f32)-0.5) * self.amp;
        }
        return .{ @intCast(frames.len), .Continue };
    }

   fn reset(ptr: *anyopaque) bool { 
       _ = ptr; 
       return true;
   }
};

