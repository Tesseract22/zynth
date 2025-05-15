const std = @import("std");


pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{});
    const opt = b.standardOptimizeOption(.{});

    const rl = b.dependency("raylib", .{});

    const exe = b.addExecutable(
        .{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = opt,
            .name = "zynth",
        }
    );
    exe.addIncludePath(rl.path("src"));
    exe.linkLibrary(rl.artifact("raylib"));
    exe.addIncludePath(b.path("src"));
    // exe.addCSourceFile(.{.file = b.path("src/main.c")});
    exe.linkLibC();

    b.installArtifact(exe);
}
