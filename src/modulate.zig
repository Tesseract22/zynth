const std = @import("std");

const Streamer = @import("streamer.zig");


pub const RingModulater = struct {
    carrier: Streamer,
    modulator: Streamer,

    pub fn streamer(self: *RingModulater) Streamer {
        return .{
            .ptr = @ptrCast(self),
            .vtable = .{
                .read = read,
                .reset = reset,
            },
        };
    }

    fn read(ptr: *anyopaque, frames: []f32) struct { u32, Streamer.Status } {
        const self: *RingModulater = @alignCast(@ptrCast(ptr));
        var tmp = [_]f32 {0} ** (1024 * 4);
        std.debug.assert(tmp.len >= frames.len);
        const len1, const status1 = self.modulator.read(tmp[0..frames.len]);
        const len2, const status2 = self.carrier.read(frames);
        const min_len = @min(len1, len2);
        for (0..min_len) |i| {
            frames[i] *= tmp[i];
        }
        for (min_len..frames.len) |i| {
            frames[i] = 0;
        }
        return .{ min_len, status1.andStatus(status2) };
    }

    fn reset(ptr: *anyopaque) bool {
        const self: *RingModulater = @alignCast(@ptrCast(ptr));
        return self.carrier.reset() and self.modulator.reset();
    }
};
