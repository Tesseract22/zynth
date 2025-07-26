const std = @import("std");

const Zynth = @import("zynth");
const Waveform = Zynth.Waveform;
const Replay = Zynth.Replay;
const Audio = Zynth.Audio;

var random = std.Random.Xoroshiro128.init(0);


pub fn main() !void {
    var string = Waveform.StringNoise.init(0.5, 440, random.random(), 1);
    var repeat = Replay.RepeatAfterStop.init(null, string.streamer());
    var ctx = Audio.SimpleAudioCtx {};
    try ctx.init(repeat.streamer());
    defer ctx.deinit();
    try ctx.start();

    Audio.wait_for_input();
}
