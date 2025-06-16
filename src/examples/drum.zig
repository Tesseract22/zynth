const std = @import("std");
const Zynth = @import("zynth");
const c = Zynth.c;
const Waveform = Zynth.Waveform;
const Envelop = Zynth.Envelop;
const Mixer = Zynth.Mixer;
const RingBuffer = Zynth.RingBuffer;
const Replay = Zynth.Replay;
const Modulate = Zynth.Modulate;
const Audio = Zynth.Audio;
const Config = Zynth.Config;
const Delay = Zynth.Delay;
const Streamer = Zynth.Streamer;
const Preset = @import("preset");


pub fn main() !void {
    const c_alloc = std.heap.c_allocator;
    var arena = std.heap.ArenaAllocator.init(c_alloc);
    defer arena.deinit();
    const a = arena.allocator();

    var mixer = Mixer {};
    var streamer = mixer.streamer();

    var ctx = Audio.SimpleAudioCtx {};
    try ctx.init(&streamer);
    try ctx.start();
    const bpm = 120.0;
    const whole_note = 60.0/bpm * 4.0;
    {
        const loop = try a.create(Replay.Repeat);
        loop.* = Replay.Repeat.init_secs(whole_note, null, try Preset.Drum.bass(a));
        mixer.play(loop.streamer());

    }  
    {
        const loop = try a.create(Replay.Repeat);
        loop.* = Replay.Repeat.init_secs(whole_note/2.0, null, try Preset.Drum.close_hi_hat(a));

        const wait = try a.create(Delay.Wait);
        wait.* = Delay.Wait.init_secs(loop.streamer(), whole_note/4.0);


        mixer.play(wait.streamer());
    }
    {
        const loop = try a.create(Replay.Repeat);
        loop.* = Replay.Repeat.init_secs(whole_note, null, try Preset.Drum.snare(a));

        const wait = try a.create(Delay.Wait);
        wait.* = Delay.Wait.init_secs(loop.streamer(), whole_note*2.0/4.0);

        mixer.play(wait.streamer());
    }
    const stdin = std.io.getStdIn();
    const reader = stdin.reader();
    _ = try reader.readByte();

}
