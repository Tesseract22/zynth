const std = @import("std");

const Zynth = @import("zynth");
const Waveform = Zynth.Waveform;
const Audio = Zynth.Audio;

pub fn main() void {
    var sine_wave = Waveform.Simple.init(0.5, 440, .Sine);
    var ctx = Audio.SimpleAudioCtx {};
    ctx.init(sine_wave.streamer()) catch unreachable;
    defer ctx.deinit();
    ctx.start() catch unreachable;
    
    Audio.wait_for_input();
}
