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
    const enable_target_suffix = b.option(bool, "enable-target-suffix", "Appends the target triple to the executable name, useful creating github releases.") orelse false;

    var dir = b.path("src/examples").getPath3(b, null).openDir(".", .{.iterate = true }) catch unreachable;
    defer dir.close();
    var it = dir.iterate();
    while (it.next() catch unreachable) |file| {
        std.debug.assert(file.kind == .file);
        std.debug.assert(std.mem.eql(u8, std.fs.path.extension(file.name), ".zig"));
        if (prefix_filter_opt) |prefix_filter| {
            if (!std.mem.startsWith(u8, file.name, prefix_filter)) continue;
        }
        const stripped = file.name[0..file.name.len-4];
        const exe_name = if (!enable_target_suffix) stripped else b.fmt("{s}-{s}-{s}-{s}", 
            .{stripped, @tagName(target.result.cpu.arch), @tagName(target.result.abi), @tagName(target.result.os.tag)});
        const exe = b.addExecutable(
            .{
                .root_source_file = b.path(b.fmt("src/examples/{s}", .{file.name})),
                .target = target,
                .optimize = opt,
                .name = exe_name,
            }
        );
        exe.root_module.addImport("zynth", zynth);
        exe.root_module.addImport("preset", preset);
        b.installArtifact(exe);
    }
}
