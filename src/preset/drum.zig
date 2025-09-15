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
const Streamer = Zynth.Streamer;

var rand = std.Random.Xoroshiro128.init(0);
var random = rand.random();

// TODO: Configurable parameters
const create = Audio.create;

pub fn bass(a: std.mem.Allocator) !Streamer {
    const mixer = create(a, Mixer {});
    {
        const hit = create(a, Waveform.BrownNoise {.white = Waveform.WhiteNoise {.amp = 0.65, .random = random }, .rc = 0.1 });
        const hit_envelop = create(a, Envelop.Envelop(.{ .static = 2 }).init(
                .{0.005},
                .{1.0, 0},
                hit.streamer()));
        mixer.play(hit_envelop.streamer());
    }
    {
        // TODO: optimize this with static
        const sine = create(a, Waveform.FreqEnvelop.init(1.0, .init(
                    try a.dupe(f64, &.{0.02, 0.12}),
                    try a.dupe(f64, &.{300, 50, 50})

        ), .Sine));
        const envelop = create(a, Envelop.Envelop(.{ .static = 3 }).init(
                .{0.02, 0.12},
                .{1, 0.4, 0.0},
                sine.streamer()
        ));
        mixer.play(envelop.streamer());
    }
    return mixer.streamer();
}

// TODO: experiment with ring modulator
pub fn close_hi_hat(a: std.mem.Allocator) !Streamer {
    const noise = create(a, Waveform.WhiteNoise {.amp = 0.15, .random = random });
    const envelop = create(a, Envelop.Envelop(.{ .static = 2 }).init(
        .{0.05},
        .{1.0, 0.0},
        noise.streamer()));
    return envelop.streamer();
}

pub fn snare(a: std.mem.Allocator) !Streamer {
    const snare_mixer = create(a, Mixer {});

    const hit = create(a, Waveform.WhiteNoise {.amp = 1, .random = random });
    const hit_envelop = create(a, Envelop.Envelop(.{ .static = 2 }).init(
        .{0.005}, 
        .{1.0, 1.0}, 
        hit.streamer()));
    snare_mixer.play(hit_envelop.streamer());

    const body = create(a, Waveform.FreqEnvelop.init(0.7, .{
        .durations = try a.dupe(f64, &.{0.01, 0.04}),
        .heights = try a.dupe(f64, &.{250, 200, 190}),
    }, .Sine));
    const body_envelop = create(a, Envelop.Envelop(.{ .static = 2 }).init(
        .{0.05}, 
        .{1, 0.0}, 
        body.streamer()));
    snare_mixer.play(body_envelop.streamer());

    const vibrate = create(a, Waveform.WhiteNoise {.amp = 0.3, .random = random });
    const vibrate_envelop = create(a, Envelop.Envelop(.{ .static = 3 }).init(
        .{0.015, 0.05}, 
        .{0, 1.0, 0}, 
        vibrate.streamer()));
    snare_mixer.play(vibrate_envelop.streamer());

    const metallic_mod = create(a, Waveform.FreqEnvelop.init(0.2, .{
        .durations = try a.dupe(f64, &.{0.04}),
        .heights = try a.dupe(f64, &.{200, 180}),
    }, .Triangle));

    const metallic_car = create(a, Waveform.FreqEnvelop.init(1, .{
        .durations = try a.dupe(f64, &.{0.04}),
        .heights = try a.dupe(f64, &.{1000, 1000}),
    }, .Sine));
    const ring_mod = create(a, Modulate.RingModulater {.modulator = metallic_mod.streamer(), .carrier = metallic_car.streamer()});
    const ring_envelop = create(a, Envelop.Envelop(.{ .static = 4 }).init(
        .{0.01, 0.007, 0.03}, 
        .{0, 0, 1, 0.0}, 
        ring_mod.streamer()));

    snare_mixer.play(ring_envelop.streamer());

    return snare_mixer.streamer();
}
