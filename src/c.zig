const Config = @import("config.zig");
pub usingnamespace  @cImport({
    if (Config.GRAPHIC) @cInclude("raylib.h");
    @cInclude("external/miniaudio.h");
});



