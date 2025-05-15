const std = @import("std");
const c = @import("c.zig");
const Waveform = @import("waveform.zig");
const DEVICE_FORMAT = c.ma_format_f32;
const DEVICE_CHANNELS = 1;
const DEVICE_SAMPLE_RATE = 48000;

const WAVEFORM_RECORD_GRANULARITY = 20;

const Error = error {
    DeviceError,
};
const RINGBUF_SIZE = 500;
pub const RingBuffer = struct {
    head: usize = 0,
    tail: usize = 0,
    count: usize = 0,
    data: [500]f32 = [_]f32{0} ** 500,
};
pub fn RingBuffer_Append(rb: *RingBuffer, el: f32) void {
    rb.tail = (rb.tail + 1) % RINGBUF_SIZE;
    if (rb.tail == rb.head) {
	rb.head = (rb.head + 1) % RINGBUF_SIZE;
    } else {
	rb.count += 1;
    }
    rb.data[rb.tail] = el;
}
pub fn RingBuffer_At(rb: RingBuffer, i: usize) f32 {
    return rb.data[(rb.head + i) % rb.count];
}
var waveform_record = RingBuffer {};
pub fn data_callback(pDevice: [*c]c.ma_device, pOutput: ?*anyopaque, pInput: ?*const anyopaque, frameCount: u32) callconv(.c) void
{
    _ = pInput;

    //printf("advance %f, time %f\n", pSineWave->advance, pSineWave->time);
    // cycle_len = 2*pi/MA_TAU_D
    const keyboard: [*]Waveform.KeyBoard = @alignCast(@ptrCast(pDevice[0].pUserData));
    const float_out: [*]f32 = @alignCast(@ptrCast(pOutput));
    std.debug.assert(4096 >= frameCount * DEVICE_CHANNELS);
    
    for (0..2) |k| {
	Waveform.keyboard_callback(&keyboard[k], float_out, frameCount);
    }


    var window_sum: f32 = 0;
    for (0..frameCount) |frame_i| {
	window_sum += float_out[frame_i * DEVICE_CHANNELS]; // only cares about the first channel
	if ((frame_i+1) % WAVEFORM_RECORD_GRANULARITY == 0) { // TODO: checks for unused frame at the end
	    RingBuffer_Append(&waveform_record, window_sum/WAVEFORM_RECORD_GRANULARITY);
	    window_sum = 0;
	}
    }
    // if (pDevice->pUserData) fwrite(float_out, 1, sizeof(float) * frameCount * DEVICE_CHANNELS, pDevice->pUserData);

}
pub fn main() !void {
    var device: c.ma_device = undefined;
    var keyboards: [2]Waveform.KeyBoard = undefined;
    var device_config = c.ma_device_config_init(c.ma_device_type_playback);
    device_config.playback.format   = DEVICE_FORMAT;
    device_config.playback.channels = DEVICE_CHANNELS;
    device_config.sampleRate        = DEVICE_SAMPLE_RATE;
    device_config.dataCallback      = data_callback;
    device_config.pUserData         = &keyboards;

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

    for (&keyboards) |*kb| {
        kb.* = Waveform.keyboard_init(device);
    }
    //const notes[] = {0, 2, 4, 5, 7, 9, 11, 12, 14, 16};
    const WINDOW_W = 1920;
    const WINDOW_H = 1080;
    c.InitWindow(WINDOW_W, WINDOW_H, "MIDI");
    c.SetTargetFPS(60);
    // const bpm = 120;
    // const t = 0;
    // const count = 0;
    // const octave = 0;
    // const progression = [][3]u32 {
    //     .{2, 5, 9},
    //     .{7, 11, 14},
    //     .{0, 4, 7},
    //     .{0, 4, 7},
    // };
    const rect_w: f32 = WINDOW_W/@as(f32, @floatFromInt(RINGBUF_SIZE));
    std.log.err("rect_w: {}", .{rect_w});
    while (!c.WindowShouldClose()) {
        c.BeginDrawing();
	{
	    c.ClearBackground(c.WHITE);
	    c.DrawLine(0, WINDOW_H/2, WINDOW_W, WINDOW_H/2, c.Color {.r = 0, .g = 0, .b = 0, .a = 0x7f});
	    for (0..RINGBUF_SIZE-1) |i| {
                const fi: f32 = @floatFromInt(i);
		const amp1: f32 = RingBuffer_At(waveform_record, i);
		const amp2: f32 = RingBuffer_At(waveform_record, i+1);
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
	Waveform.keyboard_listen_input(&keyboards[0], device);
    }
    c.CloseWindow();
    c.ma_device_uninit(&device);


}
