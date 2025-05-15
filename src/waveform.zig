const std = @import("std");
const c = @import("c.zig");

const DEVICE_CHANNELS = 1;
const DEVICE_SAMPLE_RATE = 48000;
const WAVEFORM_POOL_LEN = 32;


const math = std.math;

pub const KeyBoard = struct {
    keys: [WAVEFORM_POOL_LEN]Key,
    octave: i32,
    tone: Tone,
};

pub const KeyNote = struct {
    key: u8,
    note: i32,
};

pub const Waveform = struct {
    advance: f64,
    time: f64,
    amplitude: f64,
    frequency: f64,
    should_sustain: bool,
    is_live: bool,
};

pub const LiveSustain = struct {
    sustain_end_t: f32,
};
pub const WaveformEnvelop = struct {
    attack: f32,
    decay: f32,
    release: f32,
    sustain: LiveOrFix,
    pub const LiveOrFix = union(enum) {
        live_sustain: LiveSustain,
        fixed_sustain: f32,
    };

};

pub const WaveformStatus = enum {
    Attack,
    Decay,
    Sustain,
    Release,
    Stop,
};
pub const StringNoise = struct {
    buf: [1024]f32,
    count: c_int,
    buf_len: c_int,
    feedback: f32,
};



pub const Tone = enum {
    Sine,
    Triangle,
    Sawtooth,
    String,
};
pub const Key = struct {
    waveform: Waveform,
    state: KeyState,
    pub const KeyState = union(enum) {
        envelop: WaveformEnvelop,
        string: StringNoise,
    };
};




pub fn keyboard_init(device: c.ma_device) KeyBoard {
    var kb = KeyBoard { .keys = undefined, .octave = 0, .tone = Tone.Sine };
    for (&kb.keys) |*key| {
	key.waveform = waveform_init(0, 220, device.sampleRate, true);
    } 
    return kb;
}

pub fn keyboard_listen_input(keyboard: *KeyBoard, device: c.ma_device) void{
    const keynote_map = [_]KeyNote {
	.{ .key = c.KEY_Q, 	.note = 0},
	.{ .key = c.KEY_TWO, 	.note = 1},
	.{ .key = c.KEY_W, 	.note = 2},
	.{ .key = c.KEY_THREE,	.note = 3},
	.{ .key = c.KEY_E,	.note = 4},
	.{ .key = c.KEY_R,	.note = 5},
	.{ .key = c.KEY_FIVE,	.note = 6},
	.{ .key = c.KEY_T,	.note = 7},
	.{ .key = c.KEY_SIX,	.note = 8},
	.{ .key = c.KEY_Y,	.note = 9},
	.{ .key = c.KEY_SEVEN,	.note = 10},
	.{ .key = c.KEY_U,	.note = 11},
	.{ .key = c.KEY_I,	.note = 12},
	.{ .key = c.KEY_NINE,	.note = 13},
	.{ .key = c.KEY_O,    	.note = 14},
	.{ .key = c.KEY_ZERO,	.note = 15},
	.{ .key = c.KEY_P,	.note = 16},
    };
    for (0..keynote_map.len) |key| {
        const envelop = &keyboard.keys[key].state.envelop;
	const string = &keyboard.keys[key].state.string;
	const waveform = &keyboard.keys[key].waveform;
	const kn = keynote_map[key];

	const freq = 261.63 * @exp2(@as(f64, @floatFromInt(kn.note))/12 + @as(f64, @floatFromInt(keyboard.octave)));
	if (c.IsKeyPressed(kn.key)) {
	    waveform.* = waveform_init(0.2, freq, device.sampleRate, true);
	    switch (keyboard.tone) {
		Tone.Sine, Tone.Triangle, Tone.Sawtooth => envelop.* = init_envelop_live(0.05, 0.05, 0.10),
		Tone.String => string.* = stringnoise_init(freq),
	    }
	}
	if (c.IsKeyReleased(kn.key)) {
	    waveform.should_sustain = false;
	    //printf("key release %f\n", envelop.sustain_end_t);
	    switch (keyboard.tone) {
		Tone.Sine,
		Tone.Triangle,
		Tone.Sawtooth => envelop.sustain.live_sustain.sustain_end_t = @max(waveform.time / freq, envelop.decay),
		Tone.String => {},
	    }
	}
    }
    if (c.IsKeyReleased(c.KEY_LEFT_SHIFT)) keyboard.octave += 1;
    if (c.IsKeyReleased(c.KEY_LEFT_CONTROL)) keyboard.octave -= 1;

    if (c.IsKeyReleased(c.KEY_LEFT_ALT)) keyboard.tone = (keyboard.tone + 1) % c.Tone.LEN;
}


pub fn keyboard_callback(keyboard: *KeyBoard, float_out: [*c]f32, frameCount: u32) void {
    var tmp = [_]f32 {0} ** 4096;
    std.debug.assert(4096 >= frameCount * DEVICE_CHANNELS);
    for (0..WAVEFORM_POOL_LEN) |i| {
	const waveform = &keyboard.keys[i].waveform;
	if (waveform.amplitude <= 0) {
	    continue;
	}
	const status = switch (keyboard.tone) {
	    Tone.Sine =>      read_waveform_pcm_frames(waveform, keyboard.keys[i].state.envelop, &tmp, frameCount, ma_waveform_sine_f32),
	    Tone.Triangle =>  read_waveform_pcm_frames(waveform, keyboard.keys[i].state.envelop, &tmp, frameCount, ma_waveform_triangle_f32),
	    Tone.Sawtooth =>  read_waveform_pcm_frames(waveform, keyboard.keys[i].state.envelop, &tmp, frameCount, ma_waveform_sawtooth_f32),
	    Tone.String =>    read_string_pcm_frames(waveform.*,   &keyboard.keys[i].state.string,    &tmp, frameCount),
	};
	for (0..frameCount * DEVICE_CHANNELS) |frame_i| {
	    float_out[frame_i] += tmp[frame_i];
	}
	if (status == WaveformStatus.Stop) {
	    waveform.amplitude = 0;
	}

    }
}

pub fn ma_waveform__calculate_advance(sampleRate: u32, frequency: f64) f64 {
    return (1.0 / (@as(f64, @floatFromInt(sampleRate)) / frequency));
}

pub fn waveform_init(amp: f64, freq: f64, sample_rate: u32, is_live: bool) Waveform {
    return .{
        .amplitude = amp,
        .frequency = freq,
        .advance = ma_waveform__calculate_advance(sample_rate, freq),
        .time    = 0,
        .is_live = is_live,
        .should_sustain = true,
    };
}
pub fn init_envelop_fixed(attack: f32, decay: f32, sustain: f32, release: f32) WaveformEnvelop {
    return WaveformEnvelop {
        .attack = attack,
        .decay = attack + decay,
        .sustain = .{ .live_sustain = attack + decay + sustain },
        .release = attack + decay + sustain + release,
    };
}
pub fn init_envelop_live(attack: f32, decay: f32, release: f32) WaveformEnvelop {
    return WaveformEnvelop {
        .attack = attack,
        .decay = attack + decay,
        .release = release,
        .sustain = .{ .live_sustain =  .{.sustain_end_t = 0 } },
    };
}


var rand = std.Random.Xoshiro256.init(0);

pub fn stringnoise_init(freq: f64) StringNoise {
    var sn = StringNoise {
        .count = 0,
        .buf_len = DEVICE_SAMPLE_RATE / freq,
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
pub fn ma_waveform_sine_f32(time: f64, amplitude: f64) f32 {
    return @floatCast(@sin(2 * math.pi * time) * amplitude);
}
pub fn ma_waveform_triangle_f32(time: f64, amplitude: f64) f32 {
    const f: f64 = time - @floor(time);
    const r = 2 * @abs(2 * (f - 0.5)) - 1;

    return @floatCast(r * amplitude);
}
pub fn ma_waveform_sawtooth_f32(time: f64, amplitude: f64) f32 {
    const f: f64 = time - @floor(time);
    const r = 2 * (f - 0.5);

    return @floatCast(r * amplitude);
}
pub fn ma_waveform_square_f32(time: f64, amplitude: f64) f32 {
    const f: f64 = time - @floor(time);
    return @floatCast(if (f < 0.5) amplitude else -amplitude);
}

pub fn lerp(a: f32, b: f32, t: f32) f32 {
    return (b - a) * t + a;
}

const WaveformFn = fn (f64, f64) f32;
pub fn read_waveform_pcm_frames(
    waveform: *Waveform, 
    envelop: WaveformEnvelop, 
    pFramesOutf32: [*]f32, 
    frameCount: u64, 
    waveform_fn: *const WaveformFn) WaveformStatus {
    var status: WaveformStatus = undefined;

    for (0..frameCount) |iFrame| {
        const s = waveform_fn(waveform.time, waveform.amplitude);
        waveform.time += waveform.advance;
        const real_t = waveform.time / waveform.frequency;
        if (real_t < envelop.attack) {
            s *= lerp(0.0, 1.0, (real_t-0)/(envelop.attack-0));
            status = WaveformStatus.Attack; } else if (real_t < envelop.decay) {
            s *= lerp(1.0, 0.6, (real_t-envelop.attack)/(envelop.decay-envelop.attack));
            status = WaveformStatus.Decay;
        } else if (waveform.is_live) {
            if (waveform.should_sustain) {
                s *= 0.6;
                status = WaveformStatus.Sustain;
            } else if (real_t - envelop.live_sustain.sustain_end_t < envelop.release) {
                s *= lerp(0.6, 0.0, (real_t-envelop.live_sustain.sustain_end_t)/(envelop.release));
                status = WaveformStatus.Release;
            } else {
                s = 0;
                status = WaveformStatus.Stop;
            }
        } else {
            if (real_t < envelop.fixed_sustain) {
                s *= 0.6;
                status = WaveformStatus.Sustain;
            } else if (real_t < envelop.release) {
                s *= lerp(0.6, 0.0, (real_t-envelop.fixed_sustain)/(envelop.release-envelop.fixed_sustain));
                status = WaveformStatus.Release;
            } else {
                s = 0;
                status = WaveformStatus.Stop;
            }
        }

        for (0..DEVICE_CHANNELS) |iChannel| {
            pFramesOutf32[iFrame*DEVICE_CHANNELS + iChannel] = s;
        }
    }
    // const real_t = waveform.time / waveform.frequency;
    return status;
}
pub fn read_string_pcm_frames(waveform: Waveform, string: *StringNoise, f32_out: [*]f32, frameCount: u32) WaveformStatus {
    const feedback = string.feedback * (if (waveform.should_sustain) 1.0 else 0.9);
    for (0..frameCount) |frame_i| {
        if (frame_i > 2 * DEVICE_SAMPLE_RATE) return WaveformStatus.Stop;
        for (0..DEVICE_CHANNELS) |channel_i| {
            f32_out[frame_i * DEVICE_CHANNELS + channel_i] = string.buf[string.count] * waveform.amplitude;
        }
        const range = 2;
        const sum = 0;
        const len = string.buf_len;
        for (-range..range+1) |i| {
            const idx = ((string.count + i) % len + len) % len;
            sum += string.buf[idx];
        }
        string.buf[string.count] = sum / (range * 2 + 1) * feedback;

        //printf("sum: %f\n", sum);
        const next = (string.count + 1) % len;
        // int prev = (string.count % len + len) % len;
        // string.buf[string.count] = (string.buf[string.count] + string.buf[next] + string.buf[prev]) / 3 * feedback;
        string.count = next;
    }
    return WaveformStatus.Sustain;
}



