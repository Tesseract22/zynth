const std = @import("std");
const c = @import("c.zig");
const Streamer = @import("streamer.zig");
const Config = @import("config.zig");
const lerp = std.math.lerp;
// |..|..|..|
pub const Envelop = struct {
    durations: []const f32,
    heights: []const f32,
    t: f32,
    sub_stream: Streamer,
    pub fn init(durations: []const f32, heights: []const f32, sub_stream: Streamer) Envelop {
        std.debug.assert(durations.len > 0);
        std.debug.assert(durations.len == heights.len - 1);
        return .{ .durations = durations, .heights = heights, .t = 0, .sub_stream = sub_stream };
    }
    pub fn get(self: Envelop, t: f32) struct { f32, Streamer.Status } {
        var accum: f32 = 0;
        for (self.durations, 0..) |dura, i| {
            if (t < accum + dura) {
                return .{ lerp(self.heights[i], self.heights[i+1], (t - accum)/dura), .Continue };
            }
            accum += dura;
        } else {
            return .{ 0, .Stop };
        }
    }
    fn read(ptr: *anyopaque, frames: []f32) Streamer.Status {
        const self: *Envelop = @alignCast(@ptrCast(ptr));
        const sub_status = self.sub_stream.read(frames);
        const advance = 1.0/@as(comptime_float, @floatFromInt(Config.SAMPLE_RATE));
        var status: Streamer.Status = undefined;
        for (0..frames.len) |i| {
            self.t += advance;
            const mul, status = self.get(self.t);
            frames[i] *= mul;
        }
        if (sub_status == .Stop) return .Stop;
        return status;
    }
    pub fn streamer(self: *Envelop) Streamer {
        return .{
            .ptr = @ptrCast(self),
            .vtable = .{
                .read = read,
            },
        };
    }
};

pub const LiveEnvelop = struct {
    attack: f32,
    decay: f32,
    release: f32,
    sustain_end_t: f32,
    should_sustain: bool,
    pub fn init(attack: f32, decay: f32, release: f32) LiveEnvelop {
        return .{
            .attack = attack,
            .decay = decay,
            .release = release,
            .sustain_end_t = undefined,
        };
    }
    pub fn get(self: LiveEnvelop, t: f32) struct {f32, Status} {
        var env_mul: f32 = undefined;
        var status: Status = undefined;
        if (t < self.attack) {
            env_mul = lerp(0.0, 1.0, (t-0)/(self.attack-0));
            status = Status.Attack; 
        } else if (t < self.decay) {
            env_mul = lerp(1.0, 0.6, (t-self.attack)/(self.decay-self.attack));
            status = Status.Decay;
        } else if (self.should_sustain) {
            env_mul = 0.6;
            status = Status.Sustain;
        } else if (t - self.sustain_end_t < self.release) {
            env_mul = lerp(0.6, 0.0, (t-self.sustain_end_t)/(self.release));
            status = Status.Release;
        } else {
            env_mul = 0;
            status = Status.Stop;
        }
        return .{env_mul, status};
    }
};

pub const Status = enum {
    Attack,
    Decay,
    Sustain,
    Release,
    Stop,
};


