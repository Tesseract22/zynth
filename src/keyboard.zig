const std = @import("std");
const assert = std.debug.assert;
const c = @import("c");

const Waveform = @import("waveform.zig");
const Streamer = @import("streamer.zig");
const Envelop = Waveform.Envelop;
const KeyBoard = @This();

pub const WAVEFORM_POOL_LEN = 32;

// Design 1.
// A keyboard maps a set of keys to a set of streamer
// When key is pressed, it start reading from the corresponding streamer
// When kay is released, it calls the 'stop' method of the streamer
//
const Key = c_int; // A key, as in a key on the keyboard
pub const default_regular_key_sequence: []const Key = 
    &.{
        c.KEY_Q, c.KEY_W, c.KEY_E, c.KEY_R, c.KEY_T, c.KEY_Y, c.KEY_U, c.KEY_I, c.KEY_O, c.KEY_P,
    };
pub const default_piano_key_sequence: []const Key = 
    &.{
        c.KEY_Q, c.KEY_TWO, c.KEY_W, c.KEY_THREE, c.KEY_E, c.KEY_R, c.KEY_FIVE, c.KEY_T, c.KEY_SIX, c.KEY_Y,
	c.KEY_SEVEN, c.KEY_U, c.KEY_I, c.KEY_NINE, c.KEY_O, c.KEY_ZERO, c.KEY_P, 
    };

keys: []const Key,
streamers: []const Streamer,
playing: std.DynamicBitSetUnmanaged,

pub fn init(keys: []const Key, streamers: []const Streamer, a: std.mem.Allocator) KeyBoard {
    assert(keys.len == streamers.len);
    return .{ .keys = keys, .streamers = streamers, .playing = std.DynamicBitSetUnmanaged.initEmpty(a, keys.len) catch unreachable };
}

pub fn init_default_piano_keys(streamers: []const Streamer, a: std.mem.Allocator) KeyBoard {
    assert(streamers.len <= default_piano_key_sequence.len);
    return  init(default_piano_key_sequence[0..streamers.len], streamers, a);
}

pub fn init_default_regular_keys(streamers: []const Streamer, a: std.mem.Allocator) KeyBoard {
    assert(streamers.len <= default_regular_key_sequence.len);
    return init(default_regular_key_sequence[0..streamers.len], streamers, a);
}

pub fn listen_input(keyboard: *KeyBoard) void {
    for (keyboard.keys, keyboard.streamers, 0..) |key, stream, i| {
        if (c.IsKeyPressed(key)) {
            _ = stream.reset();
            keyboard.playing.set(i);
        }
        if (c.IsKeyReleased(key)) {
            if (!stream.stop()) {
                keyboard.playing.unset(i);
            }
        }
    }
}

fn read(ptr: *anyopaque, float_out: []f32) struct { u32, Streamer.Status } {
    const self: *KeyBoard = @alignCast(@ptrCast(ptr));
    var max_len: u32 = 0;
    for (self.streamers, 0..) |stream, i| {
        var tmp = [_]f32 {0} ** 1024; // TODO: smaller buf size
        if (!self.playing.isSet(i)) continue;
        const len, const status = stream.read(tmp[0..float_out.len]);
        for (0..len) |frame_i|
            float_out[frame_i] += tmp[frame_i];
        max_len = @max(max_len, len);
        if (status == .Stop) {
            self.playing.unset(i);
        }
    }
    return .{ max_len, Streamer.Status.Continue };
}

fn reset(ptr: *anyopaque) bool {
    const self: *KeyBoard = @alignCast(@ptrCast(ptr));
    var success = true;
    for (self.streamers, 0..) |stream, i| {
        if (!self.playing.isSet(@intCast(i))) continue;
        success = stream.reset() and success;
    }
    return success;
}

pub fn streamer(self: *KeyBoard) Streamer {
    return .{
        .ptr = @ptrCast(self),
        .vtable = .{
            .read = read,
            .reset = reset,
        }
    };
}
