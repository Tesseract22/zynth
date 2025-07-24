const c = @import("c.zig");
const Meta = @import("MetaConfig");
pub const SAMPLE_RATE = 44100;
pub const CHANNELS = 1;
pub const DEVICE_FORMAT = c.ma_format_f32;
pub const GUI = Meta.enable_gui;
pub const WAVEFORM_RECORD_GRANULARITY = 20;
pub const WAVEFORM_RECORD_RINGBUF_SIZE = 500;
