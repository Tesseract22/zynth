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
const testing = std.testing;
test "Linear Envelop" {
    const le = LinearEnvelop(f64, f64).init(&.{0.5}, &.{440, 440});
    for (0..5) |i| {
        try testing.expectEqualDeep(le.get(@as(f64, @floatFromInt(i)) * 0.1), .{ 440, .Continue });
    }

    try testing.expectEqualDeep(le.get(0.6), .{ 0, .Stop });
}
