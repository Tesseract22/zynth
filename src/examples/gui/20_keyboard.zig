const std = @import("std");

const Zynth = @import("zynth");
const c = Zynth.capi;
const Waveform = Zynth.Waveform;
const Envelop = Zynth.Envelop;
const KeyBoard = Zynth.KeyBoard;
const RingBuffer = Zynth.RingBuffer;
const Audio = Zynth.Audio;
const Config = Zynth.Config;
const Streamer = Zynth.Streamer;
const String = Zynth.Waveform.StringNoise;

fn data_callback(pDevice: [*c]c.ma_device, pOutput: ?*anyopaque, pInput: ?*const anyopaque, frameCount: u32) callconv(.c) void {
    Audio.read_frames(pDevice, pOutput, pInput, frameCount);
    const float_out: [*]f32 = @alignCast(@ptrCast(pOutput));
    var window_sum: f32 = 0;
    for (0..frameCount) |frame_i| {
        window_sum += float_out[frame_i * Config.CHANNELS]; // only cares about the first channel
        if ((frame_i+1) % Config.WAVEFORM_RECORD_GRANULARITY == 0) { // TODO: checks for unused frame at the end
            waveform_record.push(window_sum/Config.WAVEFORM_RECORD_GRANULARITY);
            window_sum = 0;
        }
    }
}
var waveform_record = RingBuffer.FixedRingBuffer(f32, Config.WAVEFORM_RECORD_RINGBUF_SIZE) {};

const total_keys = 17;
var strings: [total_keys]String = undefined;
var waveforms: [total_keys]Waveform.Simple = undefined;
var streams: [total_keys]Streamer = undefined;
var envelops: [total_keys]Envelop.LiveEnvelop = undefined;
var kb: KeyBoard = undefined;
const shape_ct = @typeInfo(Waveform.Shape).@"enum".fields.len;

var rand = std.Random.Xoroshiro128.init(0);
var random = rand.random();

fn init_keyboard_streams(shape: u32, octave: i32, a: std.mem.Allocator) void {
    if (shape == shape_ct) {
        for (0..total_keys) |k| {
            const freq = @exp2(@as(f32, @floatFromInt(k)) / 12.0 + @as(f32, @floatFromInt(octave))) * 440;
            strings[k] = String.init(0.5, freq, random);
            streams[k] = strings[k].streamer();
        }
    } else {
        for (0..total_keys) |k| {
            const freq = @exp2(@as(f32, @floatFromInt(k)) / 12.0 + @as(f32, @floatFromInt(octave))) * 440;
            waveforms[k] = Waveform.Simple.init(0.2, freq, @enumFromInt(shape));
            envelops[k] = Envelop.LiveEnvelop.init(0.05, 0.03, 0.1, waveforms[k].streamer());
            streams[k] = envelops[k].streamer();
        }
    }

    kb = KeyBoard.init_default_piano_keys(&streams, a);
}

pub fn main() !void {
    const c_alloc = std.heap.c_allocator;
    var arena = std.heap.ArenaAllocator.init(c_alloc);
    defer arena.deinit();
    const a = arena.allocator();

    var shape: u32 = 0;
    var octave: i32 = -1;

    const WINDOW_W = 1920;
    const WINDOW_H = 1080;
    c.InitWindow(WINDOW_W, WINDOW_H, "Zynth - Keyboard");
    c.SetTargetFPS(60);
    const rect_w: f32 = WINDOW_W/@as(f32, @floatFromInt(Config.WAVEFORM_RECORD_RINGBUF_SIZE));

    init_keyboard_streams(0, octave, a);
    const streamer = kb.streamer();

    var ctx = Audio.SimpleAudioCtx {};
    try ctx.init(streamer);
    ctx.device.onData = data_callback;
    try ctx.start();
    defer ctx.deinit();

    while (!c.WindowShouldClose()) {
        kb.listen_input();
        if (c.IsKeyPressed(c.KEY_LEFT_ALT)) {
            _ = streamer.reset();
            shape = (shape + 1) % @as(u32, @intCast((shape_ct + 1)));
            init_keyboard_streams(shape, octave, a);
        }
        if (c.IsKeyPressed(c.KEY_LEFT_SHIFT)) {
            octave += 1;
            _ = streamer.reset();
            init_keyboard_streams(shape, octave, a);
        }
        if (c.IsKeyPressed(c.KEY_LEFT_CONTROL)) {
            octave -= 1;
            _ = streamer.reset();
            init_keyboard_streams(shape, octave, a);
        }
        c.BeginDrawing();
        {
            c.ClearBackground(c.WHITE);
            c.DrawLine(0, WINDOW_H/2, WINDOW_W, WINDOW_H/2, c.Color {.r = 0, .g = 0, .b = 0, .a = 0x7f});
            for (0..Config.WAVEFORM_RECORD_RINGBUF_SIZE-1) |i| {
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
            const txt = 
                \\Press <Q> - <P> to play
                \\Press <ALT> to change tone
                \\Press <Left-Shift>/<Left-Control> to change octave
                ;
            c.DrawText(txt, 10, 10, 30, c.BLACK);
        }
        c.EndDrawing();
    }
    c.CloseWindow();
}
