const std = @import("std");
const c = @import("c.zig");

const Streamer = @import("streamer.zig");
const Waveform = @This();
const math = std.math;

pub const Shape = enum {
    Sine,
    Triangle,
    Sawtooth,
};

advance: f64,
time: f64,
amplitude: f64,
frequency: f64,
shape: Shape,

fn read(ptr: *anyopaque, frames: []f32) Streamer.Status {
    const self: *Waveform = @alignCast(@ptrCast(ptr));
    const func: *const fn (f64, f64) f32 = switch (self.shape) {
        .Sine => sine_f32,
        .Sawtooth => sawtooth_f32,
        .Triangle => triangle_f32,
    };
    for (0..frames.len) |i| {
        self.time += self.advance;
        frames[i] = func(self.time, self.amplitude);
    }
    return Streamer.Status.Continue;
}

pub fn streamer(self: *Waveform) Streamer {
    return .{
        .ptr = @ptrCast(self),
        .vtable = .{
            .read = read,
        },
    };
}

pub fn calculate_advance(sampleRate: u32, frequency: f64) f64 {
    return (1.0 / (@as(f64, @floatFromInt(sampleRate)) / frequency));
}

pub fn init(amp: f64, freq: f64, sample_rate: u32, shape: Shape) Waveform {
    return .{
        .amplitude = amp,
        .frequency = freq,
        .advance = calculate_advance(sample_rate, freq),
        .time    = 0,
        .shape = shape,
    };
}


// A * sin(2*pi*f * t)
pub fn sine_f32(time: f64, amplitude: f64) f32 {
    return @floatCast(@sin(2 * math.pi * time) * amplitude);
}

pub fn triangle_f32(time: f64, amplitude: f64) f32 {
    const f: f64 = time - @floor(time);
    const r = 2 * @abs(2 * (f - 0.5)) - 1;
    return @floatCast(r * amplitude);
}

pub fn sawtooth_f32(time: f64, amplitude: f64) f32 {
    const f: f64 = time - @floor(time);
    const r = 2 * (f - 0.5);
    return @floatCast(r * amplitude);
}

pub fn square_f32(time: f64, amplitude: f64) f32 {
    const f: f64 = time - @floor(time);
    return @floatCast(if (f < 0.5) amplitude else -amplitude);
}
