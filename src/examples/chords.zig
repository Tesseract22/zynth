const std = @import("std");
const Zynth = @import("zynth");
const c = Zynth.c;
const Waveform = Zynth.Waveform;
const Envelop = Zynth.Envelop;
const Mixer = Zynth.Mixer;
const RingBuffer = Zynth.RingBuffer;
const Audio = Zynth.Audio;
const Config = Zynth.Config;
const Streamer = Zynth.Streamer;

fn data_callback(pDevice: [*c]c.ma_device, pOutput: ?*anyopaque, pInput: ?*const anyopaque, frameCount: u32) callconv(.c) void {
    std.log.debug("callback", .{});
    Audio.read_frames(pDevice, pOutput, pInput, frameCount);
    const float_out: [*]f32 = @alignCast(@ptrCast(pOutput));
    var window_sum: f32 = 0;
    if (Config.GRAPHIC) {
        for (0..frameCount) |frame_i| {
            window_sum += float_out[frame_i * Config.CHANNELS]; // only cares about the first channel
            if ((frame_i+1) % Config.WAVEFORM_RECORD_GRANULARITY == 0) { // TODO: checks for unused frame at the end
                waveform_record.push(window_sum/Config.WAVEFORM_RECORD_GRANULARITY);
                window_sum = 0;
            }
        }
    }
}
var waveform_record = RingBuffer.FixedRingBuffer(f32, Config.WAVEFORM_RECORD_RINGBUF_SIZE) {};

var t: f32 = 0;
var p: u32 = 0;
var rand = std.Random.Xoroshiro128.init(0);
var random = rand.random();
fn play_progression(mixer: *Mixer, a: std.mem.Allocator, dt: f32) !void {
    const bpm = 120.0;
    // const progression = [_][3]u32 {
    //     .{2, 5, 9},
    //     .{7, 11, 14},
    //     .{0, 4, 7},
    //     .{0, 4, 7},
    // };
    const progression = [_][3]u32 {
        .{2, 11, 7},
        .{7, 4, 10},
        .{0, 4, 9},
        .{0, 5, 14},
    };
 
    
    if (t <= 0) {
        const whole_note = 1.0/bpm * 60;
        for (0..3) |ci| {
            const freq = @exp2(@as(f32, @floatFromInt(progression[p][ci])) / 12.0) * 440;
            const waveform = try a.create(Waveform.FreqEnvelop);
            waveform.* = Waveform.FreqEnvelop.init(0.1, 
                .{
                    .durations = try a.dupe(f64, &.{whole_note * 2}), 
                    .heights = try a.dupe(f64, &.{freq, freq * 1})
                }, 
                .Triangle);
            const envelop = try a.create(Envelop.Envelop);
            envelop.* = Envelop.Envelop.init(
                try a.dupe(f32, &.{0.02, 0.02, whole_note, 0.02}), 
                try a.dupe(f32, &.{0.0, 1.0, 0.6, 0.6, 0.0}), 
                waveform.streamer());
                        t += 1.0/bpm * 60.0;
            mixer.play(envelop.streamer());
        }
        p = (p + 1) % @as(u32, @intCast(progression.len));
    }
    t -= dt;
}
pub fn main() !void {
    const c_alloc = std.heap.c_allocator;
    var arena = std.heap.ArenaAllocator.init(c_alloc);
    defer arena.deinit();
    const alloc = arena.allocator();

    var mixer = Mixer {};
    // var streamer = mixer.streamer();
    var reverb = Zynth.Delay.Reverb.initRandomize(mixer.streamer(), 0.25, 1, 0.3);
    var streamer = reverb.streamer();
    var ctx = Audio.SimpleAudioCtx {};
    try ctx.init(&streamer);
    ctx.device.onData = data_callback;
    try ctx.start();
    const WINDOW_W = 1920;
    const WINDOW_H = 1080;
    c.InitWindow(WINDOW_W, WINDOW_H, "Zynth");
    c.SetTargetFPS(60);
    const rect_w: f32 = WINDOW_W/@as(f32, @floatFromInt(Config.WAVEFORM_RECORD_RINGBUF_SIZE));
    while (!c.WindowShouldClose()) {
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
        }
        c.EndDrawing();
        const dt = c.GetFrameTime();
        try play_progression(&mixer, alloc, dt);
    }
    c.CloseWindow();
}
