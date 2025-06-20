const std = @import("std");

const Zynth = @import("zynth");
const Waveform = Zynth.Waveform;
const Audio = Zynth.Audio;


pub fn main() !void {
    var sine_wave = Waveform.Simple.init(0.5, 440, .Sine);
    var streamer = sine_wave.streamer();
    var ctx = Audio.SimpleAudioCtx {};
    try ctx.init(&streamer);
    defer ctx.deinit();
    try ctx.start();

    Audio.wait_for_input();
}

