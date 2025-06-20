const std = @import("std");

//fn strip_suffix()


pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{});
    const opt = b.standardOptimizeOption(.{});
    // const enable_graphic = b.option("graphic", "whether to enable the GUI w/ raylib") orelse false;
    const rl = b.dependency("raylib", .{});
    const zynth = b.addModule("zynth", .{
        .root_source_file = b.path("src/zynth.zig"),
        .target = target,
        .optimize = opt,
        .link_libc = true,
    });
    zynth.addIncludePath(rl.path("src"));
    zynth.linkLibrary(rl.artifact("raylib"));

    const preset = b.addModule("preset", .{
        .root_source_file = b.path("src/preset/preset.zig"),
        .target = target,
        .optimize = opt,
        .link_libc = true,
    });
    preset.addImport("zynth", zynth);
    
    const prefix_filter_opt = b.option([]const u8, "example-filter", "filter the the examples to build with the prefix of the provided strings.");

    var dir = std.fs.cwd().openDir("src/examples", .{.iterate = true}) catch unreachable;
    defer dir.close();
    var it = dir.iterate();
    while (it.next() catch unreachable) |file| {
        std.debug.assert(file.kind == .file);
        std.debug.assert(std.mem.eql(u8, std.fs.path.extension(file.name), ".zig"));
        if (prefix_filter_opt) |prefix_filter| {
            if (!std.mem.startsWith(u8, file.name, prefix_filter)) continue;
        }
        std.log.info("Compiling example {s}", .{file.name});
        const exe = b.addExecutable(
            .{
                .root_source_file = b.path(b.fmt("src/examples/{s}", .{file.name})),
                .target = target,
                .optimize = opt,
                .name = file.name[0..file.name.len-4],
            }
        );
        exe.root_module.addImport("zynth", zynth);
        exe.root_module.addImport("preset", preset);
        b.installArtifact(exe);
    }
}
