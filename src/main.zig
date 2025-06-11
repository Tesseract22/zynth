const std = @import("std");
const c = @import("c.zig");
const Waveform = @import("waveform.zig");
const Envelop = @import("envelop.zig");
const Delay = @import("delay.zig");
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
    if (Config.GRAPHIC) {
        for (0..frameCount) |frame_i| {
            window_sum += float_out[frame_i * Config.CHANNELS]; // only cares about the first channel
            if ((frame_i+1) % WAVEFORM_RECORD_GRANULARITY == 0) { // TODO: checks for unused frame at the end
                waveform_record.push(window_sum/WAVEFORM_RECORD_GRANULARITY);
                window_sum = 0;
            }
        }
    }
}
var t: f32 = 0;
var p: u32 = 0;
fn play_progression(mixer: *Mixer, a: std.mem.Allocator, dt: f32) !void {
    const bpm = 120.0;
    const progression = [_][3]u32 {
        .{2, 5, 9},
        .{7, 11, 14},
        .{0, 4, 7},
        .{0, 4, 7},
    };
    if (t <= 0) {
        for (0..3) |ci| {
            const freq = @exp2(@as(f32, @floatFromInt(progression[p][ci])) / 12.0) * 440;
            const waveform = try a.create(Waveform);
            waveform.* = Waveform.init(0.1, freq, Config.SAMPLE_RATE, .Triangle);
            const envelop = try a.create(Envelop.Envelop);
            envelop.* = Envelop.Envelop.init(&.{0.02, 0.02, 1.0/bpm * 60 - 0.04, 0.02}, &.{0.0, 1.0, 0.6, 0.6, 0.0}, waveform.streamer());
            // const delay = try a.create(Delay.Reverb);
            // delay.* = Delay.Reverb.initRandomize(envelop.streamer(), 0.05, 0.3, 0.7);

            mixer.play(envelop.streamer());
        }
        t += 1.0/bpm * 60.0 * 4;
        p = (p + 1) % @as(u32, @intCast(progression.len));
    }
    t -= dt;
}
pub fn main() !void {
    const c_alloc = std.heap.c_allocator;
    var arena = std.heap.ArenaAllocator.init(c_alloc);
    defer arena.deinit();
    const alloc = arena.allocator();
    var device: c.ma_device = undefined;
    // var keyboards: [tone_count]KeyBoard = undefined;
    var mixer = Mixer {};
    var reverb = Delay.Reverb.initRandomize(mixer.streamer(), 0.25, 1, 0.3);
    var streamer = reverb.streamer();
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
    if (Config.GRAPHIC) {
        const WINDOW_W = 1920;
        const WINDOW_H = 1080;
        c.InitWindow(WINDOW_W, WINDOW_H, "MIDI");
        c.SetTargetFPS(60);
        const rect_w: f32 = WINDOW_W/@as(f32, @floatFromInt(RINGBUF_SIZE));
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
            try play_progression(&mixer, alloc, dt);
        }
        c.CloseWindow();
    } else {
        var timer = try std.time.Timer.start();
        while (true) {
            const dt: f32 = @as(f32, @floatFromInt(timer.lap())) / 1e9;
            try play_progression(&mixer, alloc, dt);
            const el = timer.read();
            std.Thread.sleep(@as(u64, @intFromFloat(1.0/60.0 * 1e9)) - el);
        }
    }
    c.ma_device_uninit(&device);
}
