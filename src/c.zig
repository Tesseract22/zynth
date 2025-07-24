const Config = @import("config.zig");
pub usingnamespace  @cImport({
    if (Config.GUI) {
        @cInclude("raylib.h");
        @cInclude("external/miniaudio.h");
    } else {
        @cInclude("miniaudio.h");
    }
});



