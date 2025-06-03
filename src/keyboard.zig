const std = @import("std");
const Waveform = @import("waveform.zig");
const Tone = Waveform.Tone;
const Envelop = Waveform.Envelop;
const c = @import("c.zig");
const KeyBoard = @This();
pub const WAVEFORM_POOL_LEN = 32;

keys: [WAVEFORM_POOL_LEN]Key,
octave: i32,
tone: Waveform.Tone,


pub const Key = struct {
    waveform: Waveform,
    state: KeyState,
    pub const KeyState = union(enum) {
        envelop: Waveform.Envelop,
        string: Waveform.StringNoise,
    };
};
    
pub const KeyNote = struct {
    key: u8,
    note: i32,
};

pub fn init(device: c.ma_device) KeyBoard {
    var kb = KeyBoard { .keys = undefined, .octave = 0, .tone = Tone.Sine };
    for (&kb.keys) |*key| {
	key.waveform = Waveform.init(0, 220, device.sampleRate);
    } 
    return kb;
}

pub fn listen_input(keyboard: *KeyBoard, device: c.ma_device) void{
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
	const waveform = &keyboard.keys[key].waveform;
	const kn = keynote_map[key];

	const freq: f32 = @floatCast(261.63 * @exp2(@as(f64, @floatFromInt(kn.note))/12 + @as(f64, @floatFromInt(keyboard.octave))));
	if (c.IsKeyPressed(kn.key)) {
	    waveform.* = Waveform.init(0.2, freq, device.sampleRate);
	    switch (keyboard.tone) {
		Tone.Sine, Tone.Triangle, Tone.Sawtooth => keyboard.keys[key].state = .{ .envelop = Envelop.init_live(0.05, 0.05, 0.10) },
		Tone.String => keyboard.keys[key].state = .{ .string = Waveform.StringNoise.init(freq) },
	    }
	}
	if (c.IsKeyReleased(kn.key)) {
	    waveform.should_sustain = false;
	    //printf("key release %f\n", envelop.sustain_end_t);
	    switch (keyboard.tone) {
		Tone.Sine,
		Tone.Triangle,
		Tone.Sawtooth => {
                    const envelop = &keyboard.keys[key].state.envelop;
                    envelop.sustain.live_sustain.sustain_end_t = @max(@as(f32, @floatCast(waveform.time)) / freq, envelop.decay);

                },
		Tone.String => {},
	    }
	}
    }
    if (c.IsKeyReleased(c.KEY_LEFT_SHIFT)) keyboard.octave += 1;
    if (c.IsKeyReleased(c.KEY_LEFT_CONTROL)) keyboard.octave -= 1;
}

pub fn read(keyboard: *KeyBoard, float_out: [*c]f32, frameCount: u32) void {
    var tmp = [_]f32 {0} ** 4096;
    std.debug.assert(4096 >= frameCount * Waveform.DEVICE_CHANNELS);
    for (0..WAVEFORM_POOL_LEN) |i| {
	const waveform = &keyboard.keys[i].waveform;
	if (waveform.amplitude <= 0) {
	    continue;
	}
	const status = switch (keyboard.tone) {
	    Tone.Sine =>      waveform.read_waveform_pcm_frames(keyboard.keys[i].state.envelop, &tmp, frameCount, Waveform.sine_f32),
	    Tone.Triangle =>  waveform.read_waveform_pcm_frames(keyboard.keys[i].state.envelop, &tmp, frameCount, Waveform.triangle_f32),
	    Tone.Sawtooth =>  waveform.read_waveform_pcm_frames(keyboard.keys[i].state.envelop, &tmp, frameCount, Waveform.sawtooth_f32),
	    Tone.String =>    waveform.read_string_pcm_frames(&keyboard.keys[i].state.string,    &tmp, frameCount),
	};
	for (0..frameCount * Waveform.DEVICE_CHANNELS) |frame_i| {
	    float_out[frame_i] += tmp[frame_i];
	}
	if (status == Waveform.Status.Stop) {
	    waveform.amplitude = 0;
	}

    }
}
