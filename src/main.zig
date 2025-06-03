const std = @import("std");
const c = @import("c.zig");
const Waveform = @import("waveform.zig");
const Envelop = @import("envelop.zig");
const Mixer = @import("mixer.zig");
const RingBuffer = @import("ring_buffer.zig");
// const KeyBoard = @import("keyboard.zig");
const Config = @import("config.zig");
const Streamer = @import("streamer.zig");

const WAVEFORM_RECORD_GRANULARITY = 20;

const Error = error {
    DeviceError,
};

const RINGBUF_SIZE = 500;

var waveform_record = RingBuffer.FixedRingBuffer(f32, RINGBUF_SIZE) {};

pub fn data_callback(pDevice: [*c]c.ma_device, pOutput: ?*anyopaque, pInput: ?*const anyopaque, frameCount: u32) callconv(.c) void
{
    _ = pInput;
    // const keyboard: [*]KeyBoard = @alignCast(@ptrCast(pDevice[0].pUserData));
    const streamer: *Streamer = @alignCast(@ptrCast(pDevice[0].pUserData));
    const float_out: [*]f32 = @alignCast(@ptrCast(pOutput));
    _ = streamer.read(float_out[0..frameCount]);
    var window_sum: f32 = 0;
    for (0..frameCount) |frame_i| {
	window_sum += float_out[frame_i * Config.CHANNELS]; // only cares about the first channel
	if ((frame_i+1) % WAVEFORM_RECORD_GRANULARITY == 0) { // TODO: checks for unused frame at the end
	    waveform_record.push(window_sum/WAVEFORM_RECORD_GRANULARITY);
	    window_sum = 0;
	}
    }
}

pub fn main() !void {
    const alloc = std.heap.c_allocator;
    var device: c.ma_device = undefined;
    // var keyboards: [tone_count]KeyBoard = undefined;
    var mixer = Mixer {};
    var streamer = mixer.streamer();
    var device_config = c.ma_device_config_init(c.ma_device_type_playback);
    device_config.playback.format   = Config.DEVICE_FORMAT;
    device_config.playback.channels = Config.CHANNELS;
    device_config.sampleRate        = Config.SAMPLE_RATE;
    device_config.dataCallback      = data_callback;
    device_config.pUserData         = &streamer;

    if (c.ma_device_init(null, &device_config, &device) != c.MA_SUCCESS) {
	std.log.err("Failed to open playback device.", .{});
	return error.DeviceError;
    }
    defer c.ma_device_uninit(&device);

    std.log.info("Device Name: {s}", .{device.playback.name});

    if (c.ma_device_start(&device) != c.MA_SUCCESS) {
	std.log.err("Failed to start playback device.", .{});
	return error.DeviceError;
    }

    //const notes[] = {0, 2, 4, 5, 7, 9, 11, 12, 14, 16};
    const WINDOW_W = 1920;
    const WINDOW_H = 1080;
    c.InitWindow(WINDOW_W, WINDOW_H, "MIDI");
    c.SetTargetFPS(60);
    const bpm = 120.0;
    var t: f32 = 0;
    var p: u32 = 0;
    const progression = [_][3]u32 {
        .{2, 5, 9},
        .{7, 11, 14},
        .{0, 4, 7},
        .{0, 4, 7},
    };
    
    const rect_w: f32 = WINDOW_W/@as(f32, @floatFromInt(RINGBUF_SIZE));
    // var waveform_ringbuffer = RingBuffer.FixedRingBuffer(Waveform, 32) {};
    // var waveform = Waveform.init(1, 440, Config.SAMPLE_RATE);
    // mixer.play(waveform.streamer());
    while (!c.WindowShouldClose()) {
        c.BeginDrawing();
	{
	    c.ClearBackground(c.WHITE);
	    c.DrawLine(0, WINDOW_H/2, WINDOW_W, WINDOW_H/2, c.Color {.r = 0, .g = 0, .b = 0, .a = 0x7f});
	    for (0..RINGBUF_SIZE-1) |i| {
                const fi: f32 = @floatFromInt(i);
		const amp1: f32 = waveform_record.at(@intCast(i));
		const amp2: f32 = waveform_record.at(@intCast(i+1));
		const h1: f32 = WINDOW_H/2 * amp1;
		const h2: f32 = WINDOW_H/2 * amp2;
		c.DrawLineV(
			c.Vector2 {.x = fi * rect_w, .y = WINDOW_H/2-h1}, 
			c.Vector2 {.x = (fi+1) * rect_w, .y = WINDOW_H/2-h2},
			c.RED
			);
	    }
	}
	c.EndDrawing();
        const dt = c.GetFrameTime();
        if (t <= 0) {
            for (0..3) |ci| {
                const freq = @exp2(@as(f32, @floatFromInt(progression[p][ci])) / 12.0) * 440;
                const waveform = try alloc.create(Waveform);
                waveform.* = Waveform.init(0.3, freq, Config.SAMPLE_RATE);
                const envelop = try alloc.create(Envelop.Envelop);
                envelop.* = Envelop.Envelop.init(&.{0.02, 0.02, 1.0/bpm * 60 - 0.04, 0.02}, &.{0.0, 1.0, 0.6, 0.6, 0.0}, waveform.streamer());
                // waveform_ringbuffer.push(Waveform.init(0.3, freq, Config.SAMPLE_RATE));
                // const wave_streamer = waveform_ringbuffer.last().streamer();
                mixer.play(envelop.streamer());
            }
            t += 1.0/bpm * 60.0 * 4;
            p = (p + 1) % @as(u32, @intCast(progression.len));
        }
        t -= dt;
    }
    c.CloseWindow();
    c.ma_device_uninit(&device);
}
