const std = @import("std");
const c = @import("c.zig");

const Waveform = @This();
pub const DEVICE_CHANNELS = 1;
pub const DEVICE_SAMPLE_RATE = 48000;


const math = std.math;

advance: f64,
time: f64,
amplitude: f64,
frequency: f64,
should_sustain: bool,

pub const LiveSustain = struct {
    sustain_end_t: f32,
};
// |..|..|..|
pub const Envelop2 = struct {
    durations: []f32,
    heights: []f32,
    pub fn init(durations: []f32, heights: []f32) Envelop2 {
        std.debug.assert(durations > 0);
        std.debug.assert(durations.len == heights.len - 1);
        return .{ .durations = durations, .heights = heights };
    }
    pub fn get(self: Envelop2, t: f32) f32 {
        var accum: f32 = 0;
        for (self.durations, 0..) |dura, i| {
            if (t < accum + dura) {
                return lerp(self.heights[i], self.heights[i+1], (t - accum)/dura);
            }
            accum += dura;
        } else {
            return 0;
        }
    }
};
pub const Envelop = struct {
    attack: f32,
    decay: f32,
    release: f32,
    sustain: LiveOrFix,
    pub const LiveOrFix = union(enum) {
        live_sustain: LiveSustain,
        fixed_sustain: f32,
    };
    pub fn init_fixed(attack: f32, decay: f32, sustain: f32, release: f32) Envelop {
        return Envelop {
            .attack = attack,
            .decay = attack + decay,
            .sustain = .{ .live_sustain = attack + decay + sustain },
            .release = attack + decay + sustain + release,
        };
    }
    pub fn init_live(attack: f32, decay: f32, release: f32) Envelop {
        return Envelop {
            .attack = attack,
            .decay = attack + decay,
            .release = release,
            .sustain = .{ .live_sustain =  .{.sustain_end_t = 0 } },
        };
    }
    pub fn get(envelop: Envelop, real_t: f32, should_sustain: bool) struct {f32, Status} {
        var env_mul: f32 = undefined;
        var status: Status = undefined;
        if (real_t < envelop.attack) {
            env_mul = lerp(0.0, 1.0, (real_t-0)/(envelop.attack-0));
            status = Status.Attack; 
        } else if (real_t < envelop.decay) {
            env_mul = lerp(1.0, 0.6, (real_t-envelop.attack)/(envelop.decay-envelop.attack));
            status = Status.Decay;
        } else {
            switch (envelop.sustain) {
                .live_sustain => |sustain| {
                    if (should_sustain) {
                        env_mul = 0.6;
                        status = Status.Sustain;
                    } else if (real_t - sustain.sustain_end_t < envelop.release) {
                        env_mul = lerp(0.6, 0.0, (real_t-sustain.sustain_end_t)/(envelop.release));
                        status = Status.Release;
                    } else {
                        env_mul = 0;
                        status = Status.Stop;
                    }
                },
                .fixed_sustain => |sustain| {
                    if (real_t < sustain) {
                        env_mul = 0.6;
                        status = Status.Sustain;
                    } else if (real_t < envelop.release) {
                        env_mul = lerp(0.6, 0.0, (sustain)/(envelop.release-sustain));
                        status = Status.Release;
                    } else {
                        env_mul = 0;
                        status = Status.Stop;
                    }
                }
            }
        }
        return .{env_mul, status};
    }
};

pub const Status = enum {
    Attack,
    Decay,
    Sustain,
    Release,
    Stop,
};
pub const StringNoise = struct {
    buf: [1024]f32,
    count: u32,
    buf_len: u32,
    feedback: f32,
    pub fn init(freq: f64) StringNoise {
        var sn = StringNoise {
            .count = 0,
            .buf_len = @intFromFloat(DEVICE_SAMPLE_RATE / freq),
            .feedback = 0.996,                       
            .buf = undefined,
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
};

pub const Tone = enum {
    Sine,
    Triangle,
    Sawtooth,
    String,
};

pub fn calculate_advance(sampleRate: u32, frequency: f64) f64 {
    return (1.0 / (@as(f64, @floatFromInt(sampleRate)) / frequency));
}

pub fn init(amp: f64, freq: f64, sample_rate: u32) Waveform {
    return .{
        .amplitude = amp,
        .frequency = freq,
        .advance = calculate_advance(sample_rate, freq),
        .time    = 0,
        .should_sustain = true,
    };
}

var rand = std.Random.Xoshiro256.init(0);


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

pub fn lerp(a: f32, b: f32, t: f32) f32 {
    return (b - a) * t + a;
}

const WaveformFn = fn (f64, f64) f32;
pub fn read_waveform_pcm_frames(
    waveform: *Waveform, 
    envelop: Envelop, 
    pFramesOutf32: [*]f32, 
    frameCount: u64, 
    waveform_fn: *const WaveformFn) Status {
    var status: Status = undefined;

    for (0..frameCount) |iFrame| {
        const s = waveform_fn(waveform.time, waveform.amplitude);
        const real_t: f32 = @floatCast(waveform.time / waveform.frequency);
        //waveform.time += waveform.advance;
        const env_mul, status = envelop.get(real_t, waveform.should_sustain);
        for (0..DEVICE_CHANNELS) |iChannel| {
            pFramesOutf32[iFrame*DEVICE_CHANNELS + iChannel] = s * env_mul;
        }
        waveform.time += calculate_advance(DEVICE_SAMPLE_RATE, waveform.frequency);
    }
    // const real_t = waveform.time / waveform.frequency;
    return status;
}

pub fn read_string_pcm_frames(waveform: Waveform, string: *StringNoise, f32_out: [*]f32, frameCount: u32) Status {
    const feedback_decay: f32 = if (waveform.should_sustain) 1.0 else 0.9;
    const feedback: f32 = string.feedback * feedback_decay;
    for (0..frameCount) |frame_i| {
        for (0..DEVICE_CHANNELS) |channel_i| {
            f32_out[frame_i * DEVICE_CHANNELS + channel_i] = string.buf[string.count] * @as(f32, @floatCast(waveform.amplitude));
        }
        const range = 2;
        var sum: f32 = 0;
        const len: i32 = @intCast(string.buf_len);
        var i: i32 = -range;
        while (i <= range) : (i += 1) {
            const idx = @mod(@as(i32, @intCast(string.count)) + i, len);
            sum += string.buf[@intCast(idx)];
        }
        string.buf[string.count] = sum / (range * 2 + 1) * feedback;

        //printf("sum: %f\n", sum);
        const next = (string.count + 1) % string.buf_len;
        // int prev = (string.count % len + len) % len;
        // string.buf[string.count] = (string.buf[string.count] + string.buf[next] + string.buf[prev]) / 3 * feedback;
        string.count = next;
    }
    return Status.Sustain;
}
