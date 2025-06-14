const std = @import("std");


pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{});
    const opt = b.standardOptimizeOption(.{});
    // const enable_graphic = b.option("graphic", "whether to enable the GUI w/ raylib") orelse false;
    const rl = b.dependency("raylib", .{});
    var dir = std.fs.cwd().openDir("src/examples", .{.iterate = true}) catch unreachable;
    const zynth = b.addModule("zynth", .{
        .root_source_file = b.path("src/zynth.zig"),
        .target = target,
        .optimize = opt,
        .link_libc = true,
    });
    zynth.addIncludePath(rl.path("src"));
    zynth.linkLibrary(rl.artifact("raylib"));
    defer dir.close();
    var it = dir.iterate();
    while (it.next() catch unreachable) |file| {
        std.debug.assert(file.kind == .file);
        std.log.info("Compiling file {s}", .{file.name});
        const exe = b.addExecutable(
            .{
                .root_source_file = b.path(b.fmt("src/examples/{s}", .{file.name})),
                .target = target,
                .optimize = opt,
                .name = file.name,
            }
        );
        exe.root_module.addImport("zynth", zynth);
        b.installArtifact(exe);
    }
}
