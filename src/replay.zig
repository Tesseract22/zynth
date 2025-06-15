const std = @import("std");
const Streamer = @import("streamer.zig");
const Config = @import("config.zig");

pub const Repeat = struct {
    sub_streamer: Streamer,
    count_init: ?u32,
    interval: u32,

    count: u32 = 0,
    samples_elasped: u32 = 0,
    curr: u32 = 0,

    pub fn init_samples(interval_samples: u32, count: ?u32, sub_streamer: Streamer) Repeat {
        return .{ .sub_streamer = sub_streamer, .count_init = count, .interval = interval_samples };
    } 

    pub fn init_secs(interval_secs: f32, count: ?u32, sub_streamer: Streamer) Repeat {
        return init_samples(@intFromFloat(interval_secs*Config.SAMPLE_RATE), count, sub_streamer);
    }

    fn read(ptr: *anyopaque, frames: []f32) struct { u32, Streamer.Status } {
        const self: *Repeat = @alignCast(@ptrCast(ptr));
        while (self.curr < frames.len) {
            const len, _ = self.sub_streamer.read(frames[self.curr..]);
            self.curr += len;
            self.samples_elasped += len;
            // The sub stream is still playing, but we need to reset
            if (self.samples_elasped >= self.interval) {
                _ = self.sub_streamer.reset();
                // if the sub stream plays shorter than the interval.
                if (self.samples_elasped > len)
                    self.curr += (self.samples_elasped - len);
                self.samples_elasped = 0;
            } else if (len == 0) { // no more things to play from sub stream, wait until reset
                self.curr += (self.interval - self.samples_elasped);
                _ = self.sub_streamer.reset();
                self.samples_elasped = 0;
            }
        }
        self.curr -= @intCast(frames.len);
        return .{ @intCast(frames.len), .Continue };
    }

    fn reset(ptr: *anyopaque) bool {
        const self: *Repeat = @alignCast(@ptrCast(ptr));
        self.count = 0;
        self.samples_elasped = 0;
        self.curr = 0;
        return self.sub_streamer.reset();

    }

    pub fn streamer(self: *Repeat) Streamer {
        return .{
            .ptr = @ptrCast(self),
            .vtable = .{
                .read = read,
                .reset = reset,
            },
        };
    }
};
