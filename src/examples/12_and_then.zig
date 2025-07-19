const std = @import("std");

const Zynth = @import("zynth");
const AndThen = Zynth.Delay.AndThen;
const Cutoff = Zynth.Envelop.SimpleCutoff;
const Waveform = Zynth.Waveform;
const Audio = Zynth.Audio;


pub fn main() !void {
    var sine_wave = Waveform.Simple.init(0.5, 440, .Sine);
    var envelop1 = Cutoff {.cutoff_sec = 1, .sub_stream = sine_wave.streamer() };
    var triangle_wave = Waveform.Simple.init(0.5, 440, .Triangle);
    var envelop2 = Cutoff {.cutoff_sec = 1, .sub_stream = triangle_wave.streamer() };
    
    var and_then = AndThen {.lhs = envelop1.streamer(), .rhs = envelop2.streamer()};
    var ctx = Audio.SimpleAudioCtx {};
    try ctx.init(and_then.streamer());
    defer ctx.deinit();
    try ctx.start();

    ctx.drain();
}

