const c = @import("c");
const Streamer = @import("streamer.zig");
const Config = @import("config.zig");
const std = @import("std");

const AudioCallBack = fn (pDevice: [*c]c.ma_device, pOutput: ?*anyopaque, pInput: ?*const anyopaque, frameCount: u32) callconv(.c) void;

pub fn create(a: std.mem.Allocator, val: anytype) *@TypeOf(val) {
    const res = a.create(@TypeOf(val)) catch unreachable;
    res.* = val;
    return res;
}

pub fn wait_for_input() void {
    var stdin = std.fs.File.stdin();
    var buf: [1]u8 = undefined;
    var reader = stdin.reader(&buf);
    reader.interface.readSliceAll(&buf) catch unreachable;
}

pub fn read_frames(pDevice: [*c]c.ma_device, pOutput: ?*anyopaque, pInput: ?*const anyopaque, frameCount: u32) callconv(.c) void {
    _ = pInput;
    const ctx: *SimpleAudioCtx = @alignCast(@ptrCast(pDevice[0].pUserData));
    const float_out: [*]f32 = @alignCast(@ptrCast(pOutput));
    _, const status = ctx.streamer.read(float_out[0..frameCount]);
    if (status == .Stop) std.debug.assert(c.ma_event_signal(&ctx.stop_event) == c.MA_SUCCESS);
}

pub fn init_device_config(callback: *const AudioCallBack, ctx: *SimpleAudioCtx) c.ma_device_config {
    var device_config = c.ma_device_config_init(c.ma_device_type_playback);
    device_config.playback.format   = Config.DEVICE_FORMAT;
    device_config.playback.channels = Config.CHANNELS;
    device_config.sampleRate        = Config.SAMPLE_RATE;
    device_config.dataCallback      = callback;
    device_config.pUserData         = ctx;
    return device_config;
}

const Error = error {
    DeviceError,
    EventError,
};

pub const SimpleAudioCtx = struct {
    stop_event: c.ma_event = undefined, 
    device: c.ma_device = undefined,
    device_config: c.ma_device_config = undefined,
    streamer: Streamer = undefined,

    pub fn init(ctx: *SimpleAudioCtx, streamer: Streamer) !void {
        if (c.ma_event_init(&ctx.stop_event) != c.MA_SUCCESS) {
            std.log.err("Failed to init stop event", .{});
            return error.EventError;

        }
        ctx.streamer = streamer;
        ctx.device_config = init_device_config(read_frames, ctx);
        if (c.ma_device_init(null, &ctx.device_config, &ctx.device) != c.MA_SUCCESS) {
            std.log.err("Failed to open playback device.", .{});
            return error.DeviceError;
        }
    }
    
    pub fn start(self: *SimpleAudioCtx) !void {
        if (c.ma_device_start(&self.device) != c.MA_SUCCESS) {
            std.log.err("Failed to start playback device.", .{});
            return error.DeviceError;
        }
    }

    pub fn drain(self: *SimpleAudioCtx) void {
       std.debug.assert(c.ma_event_wait(&self.stop_event) == c.MA_SUCCESS);
    }

    pub fn deinit(self: *SimpleAudioCtx) void {
        c.ma_device_uninit(&self.device);
  }
};
