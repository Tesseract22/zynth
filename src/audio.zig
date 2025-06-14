const c = @import("c.zig");
const Streamer = @import("streamer.zig");
const Config = @import("config.zig");
const std = @import("std");

const AudioCallBack = fn (pDevice: [*c]c.ma_device, pOutput: ?*anyopaque, pInput: ?*const anyopaque, frameCount: u32) callconv(.c) void;

pub fn read_frames(pDevice: [*c]c.ma_device, pOutput: ?*anyopaque, pInput: ?*const anyopaque, frameCount: u32) callconv(.c) void
{
    _ = pInput;
    const streamer: *Streamer = @alignCast(@ptrCast(pDevice[0].pUserData));
    const float_out: [*]f32 = @alignCast(@ptrCast(pOutput));
    _ = streamer.read(float_out[0..frameCount]);
}

pub fn init_device_config(callback: *const AudioCallBack, streamer: *Streamer) c.ma_device_config {
    var device_config = c.ma_device_config_init(c.ma_device_type_playback);
    device_config.playback.format   = Config.DEVICE_FORMAT;
    device_config.playback.channels = Config.CHANNELS;
    device_config.sampleRate        = Config.SAMPLE_RATE;
    device_config.dataCallback      = callback;
    device_config.pUserData         = streamer;
    return device_config;
}

const Error = error {
    DeviceError,
};

pub const SimpleAudioCtx = struct {
    device: c.ma_device = undefined,
    device_config: c.ma_device_config = undefined,
    // pub fn init(streamer: *Streamer) Error!SimpleAudioCtx {
    //     var res: SimpleAudioCtx = undefined;
    //     try res.init_impl(streamer);
    //     return res;
    // }

    pub fn init(ctx: *SimpleAudioCtx, streamer: *Streamer) !void {
        ctx.device_config = init_device_config(read_frames, streamer);
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

    pub fn deinit(self: *SimpleAudioCtx) void {
        c.ma_device_uninit(&self.device);
    }
};
