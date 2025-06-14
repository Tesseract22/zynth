const std = @import("std");
const Zynth = @import("zynth");
const c = Zynth.c;
const Waveform = Zynth.Waveform;
const Envelop = Zynth.Envelop;
const Mixer = Zynth.Mixer;
const RingBuffer = Zynth.RingBuffer;
const Replay = Zynth.Replay;
const Audio = Zynth.Audio;
const Config = Zynth.Config;
const Streamer = Zynth.Streamer;

var rand = std.Random.Xoroshiro128.init(0);
var random = rand.random();

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
    // {
    //     const sine = try a.create(Waveform.FreqEnvelop);
    //     sine.* = Waveform.FreqEnvelop.init(0.7, Envelop.LinearEnvelop(f64, f64).init(
    //             try a.dupe(f64, &.{0.02, 0.5}), 
    //             try a.dupe(f64, &.{300, 50, 50})

    //     ), .Sine);
    //     const envelop = try a.create(Envelop.Envelop);
    //     envelop.* = Envelop.Envelop.init(
    //         try a.dupe(f32, &.{0.02, 0.02, 0.4, 0.02}), 
    //         try a.dupe(f32, &.{0.0, 1.0, 0.8, 0.6, 0.0}), 
    //         sine.streamer()
    //     );
    //     const loop = try a.create(Replay.Repeat);
    //     loop.* = Replay.Repeat.init_secs(whole_note/2.0, null, envelop.streamer());

    //     mixer.play(loop.streamer());
    // }
    // {
    //     const noise = try a.create(Waveform.Noise);
    //     noise.amp = 0.1;
    //     noise.random = random;
    //     const envelop = try a.create(Envelop.Envelop);
    //     envelop.* = Envelop.Envelop.init(
    //         try a.dupe(f32, &.{0.02, 0.05}), 
    //         try a.dupe(f32, &.{0.0, 1.0, 0.0}), 
    //         noise.streamer());

    //     const loop = try a.create(Replay.Repeat);
    //     loop.* = Replay.Repeat.init_secs(whole_note/4.0, null, envelop.streamer());

    //     mixer.play(loop.streamer());
    // }
    {
        {
            const ring = try a.create(Waveform.Simple);
            ring.* = Waveform.Simple.init(0.5, 440, .Sine);
            const envelop = try a.create(Envelop.Envelop);
            envelop.* = Envelop.Envelop.init(
                try a.dupe(f32, &.{0.001, 0.05}), 
                try a.dupe(f32, &.{0.0, 1.0, 0.0}), 
                ring.streamer());
            const loop = try a.create(Replay.Repeat);
            loop.* = Replay.Repeat.init_secs(whole_note/4.0, null, envelop.streamer());
            mixer.play(loop.streamer());
   
        }
        
        const noise = try a.create(Waveform.Noise);
        noise.amp = 0.0;
        noise.random = random;
        const envelop = try a.create(Envelop.Envelop);
        envelop.* = Envelop.Envelop.init(
            try a.dupe(f32, &.{0.02, 0.5}), 
            try a.dupe(f32, &.{0.0, 1.0, 0.0}), 
            noise.streamer());

        const loop = try a.create(Replay.Repeat);
        loop.* = Replay.Repeat.init_secs(whole_note/4.0, null, envelop.streamer());

        mixer.play(loop.streamer());
    }
    const stdin = std.io.getStdIn();
    const reader = stdin.reader();
    _ = try reader.readByte();

}
