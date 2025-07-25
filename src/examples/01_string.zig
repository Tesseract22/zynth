const std = @import("std");

const Zynth = @import("zynth");
const Waveform = Zynth.Waveform;
const Audio = Zynth.Audio;

var random = std.Random.Xoroshiro128.init(0);


pub fn main() !void {
    var string = Waveform.StringNoise.init(0.5, 440, random.random(), 1);
    var ctx = Audio.SimpleAudioCtx {};
    try ctx.init(string.streamer());
    defer ctx.deinit();
    try ctx.start();

    ctx.drain();
}
