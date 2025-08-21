pub const capi = @import("c");
pub const Audio = @import("audio.zig");
pub const Config = @import("config.zig");
pub const Delay = @import("delay.zig");
pub const Envelop = @import("envelop.zig");
pub const KeyBoard = @import("keyboard.zig");
pub const Mixer = @import("mixer.zig");
pub const Modulate = @import("modulate.zig");
pub const Replay = @import("replay.zig");
pub const RingBuffer = @import("ring_buffer.zig");
pub const Streamer = @import("streamer.zig");
pub const Waveform = @import("waveform.zig");
// pub const CompilerRt = @import("compiler_rt.zig");
// 
// comptime {
// 
// std.testing.refAllDecls(CompilerRt);
// }

pub const SimpleAudioCtx = Audio.SimpleAudioCtx;

pub const NoteDuration = enum(u8) {
    Whole = 0,
    Half = 1,
    Quarter = 2,
    Eighth = 3,
    Sixteenth = 4,
    _,

    pub fn to_sec(self: NoteDuration, bpm: f32) f32 {
        return (60.0 / bpm) * 4.0 / @exp2(@as(f32, @floatFromInt(@intFromEnum(self))));
    }
    
};

// 0 is the C3, the middle C
pub fn pitch_to_freq(p: i32) f32 {
   return 130.81 * @exp2(@as(f32, @floatFromInt(p))/12.0);
}

const std = @import("std");
const builtin = @import("builtin");

// use this overwrite options in case of emscripten
pub const std_options = if (builtin.target.os.tag == .emscripten) std.Options{
    .logFn = @import("zemscripten").log,
} else .{};
