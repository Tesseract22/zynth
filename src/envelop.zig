const std = @import("std");
const c = @import("c.zig");
const Streamer = @import("streamer.zig");
const Config = @import("config.zig");
const lerp = std.math.lerp;

pub fn LinearEnvelop(comptime DuraT: type, comptime ValT: type) type{
    return struct {
        const Self = @This();
        durations: []const DuraT,
        heights: []const ValT,

        pub fn init(durations: []const DuraT, heights: []const ValT) Self {
            std.debug.assert(durations.len > 0);
            std.debug.assert(durations.len == heights.len - 1);
            return .{ .durations = durations, .heights = heights };
        }
        pub fn get(self: Self, t: DuraT) struct { ValT, Streamer.Status } {
            var accum: DuraT = 0;
            for (self.durations, 0..) |dura, i| {
                if (t < accum + dura) {
                    return .{ lerp(self.heights[i], self.heights[i+1], (t - accum)/dura), .Continue };
                }
                accum += dura;
            } else {
                return .{ 0, .Stop };
            }
        }
    };
}

pub const Envelop = struct {
    le: LinearEnvelop(f32, f32),
    t: f32,
    sub_stream: Streamer,

    pub fn init(durations: []const f32, heights: []const f32, sub_stream: Streamer) Envelop {
        return .{ .le = LinearEnvelop(f32, f32).init(durations, heights), .t = 0, .sub_stream = sub_stream };
    }

    fn read(ptr: *anyopaque, frames: []f32) struct { u32, Streamer.Status } {
        const self: *Envelop = @alignCast(@ptrCast(ptr));
        const len, const sub_status = self.sub_stream.read(frames);
        const advance = 1.0/@as(comptime_float, @floatFromInt(Config.SAMPLE_RATE));
        for (0..frames.len) |i| {
            self.t += advance;
            const mul, const status = self.le.get(self.t);
            frames[i] *= mul;
            if (status == .Stop) {
                @memset(frames[i..], 0);
                return .{ @intCast(i), .Stop };
            }
        } else {
            return .{ len, sub_status };
        }
    }

    pub fn streamer(self: *Envelop) Streamer {
        return .{
            .ptr = @ptrCast(self),
            .vtable = .{
                .read = read,
                .reset = reset,
            },
        };
    }

    fn reset(ptr: *anyopaque) bool {
        const self: *Envelop = @alignCast(@ptrCast(ptr));
        self.t = 0;
        return self.sub_stream.reset();
    }

};

pub const LiveEnvelop = struct {
    attack: f64,
    decay: f64,
    release: f64,

    t: f64 = 0,
    should_sustain: bool = true,
    sustain_end_t: f64 = undefined,
    
    sub_stream: Streamer,

    pub fn init(attack: f32, decay: f32, release: f32, sub_stream: Streamer) LiveEnvelop {
        return .{
            .attack = attack,
            .decay = attack + decay,
            .release = release,
            .sub_stream = sub_stream,
        };
    }

    pub fn get(self: LiveEnvelop, t: f64) struct { f64, Streamer.Status } {
        var env_mul: f64 = undefined;
        var status: Streamer.Status = .Continue;
        if (t < self.attack) {
            env_mul = lerp(0.0, 1.0, (t-0)/(self.attack-0));
        } else if (t < self.decay) {
            env_mul = lerp(1.0, 0.6, (t-self.attack)/(self.decay-self.attack));
        } else if (self.should_sustain) {
            env_mul = 0.6;
        } else if (t - self.sustain_end_t < self.release) {
            env_mul = lerp(0.6, 0.0, (t-self.sustain_end_t)/(self.release));
        } else {
            env_mul = 0;
            status = .Stop;
        }
        return .{env_mul, status};
    }

    fn read(ptr: *anyopaque, frames: []f32) struct { u32, Streamer.Status } {
        const self: *LiveEnvelop = @alignCast(@ptrCast(ptr));
        const len, const sub_status = self.sub_stream.read(frames);
        const advance = 1.0/@as(comptime_float, @floatFromInt(Config.SAMPLE_RATE));
        for (0..frames.len) |i| {
            self.t += advance;
            const mul, const status = self.get(self.t);
            frames[i] *= @floatCast(mul);
            if (status == .Stop) {
                @memset(frames[i..], 0);
                return .{ @intCast(i), .Stop };
            }
        } else {
            return .{ len, sub_status };
        }
    }

    fn reset(ptr: *anyopaque) bool {
        const self: *LiveEnvelop = @alignCast(@ptrCast(ptr));
        self.t = 0;
        self.should_sustain = true;
        self.sustain_end_t = 0;
        return self.sub_stream.reset();
    }

    fn stop(ptr: *anyopaque) bool {
        const self: *LiveEnvelop = @alignCast(@ptrCast(ptr));
        self.should_sustain = false;
        self.sustain_end_t = @max(self.decay, self.t);
        return true;
    }

    pub fn streamer(self: *LiveEnvelop) Streamer {
        return .{
            .ptr = @ptrCast(self),
            .vtable = .{
                .read = read,
                .reset = reset,
                .stop = stop,
            },
        };
    }
};

const testing = std.testing;
test "Linear Envelop" {
    const le = LinearEnvelop(f64, f64).init(&.{0.5}, &.{440, 440});
    for (0..5) |i| {
        try testing.expectEqualDeep(le.get(@as(f64, @floatFromInt(i)) * 0.1), .{ 440, .Continue });
    }

    try testing.expectEqualDeep(le.get(0.6), .{ 0, .Stop });
}
