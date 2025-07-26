const std = @import("std");

fn compile_dir(
    b: *std.Build,
    target: std.Build.ResolvedTarget, 
    opt: std.builtin.OptimizeMode,
    path: []const u8,
    enable_target_suffix: bool,
    prefix_filter_opt: ?[]const u8,
    zynth: *std.Build.Module,
    preset: *std.Build.Module) void {
    var dir = b.path(path).getPath3(b, null).openDir(".", .{.iterate = true }) catch unreachable;
    defer dir.close();
    var it = dir.iterate();
    while (it.next() catch unreachable) |file| {
        if (file.kind != .file) continue;
        std.debug.assert(std.mem.eql(u8, std.fs.path.extension(file.name), ".zig"));
        if (prefix_filter_opt) |prefix_filter| {
            if (!std.mem.startsWith(u8, file.name, prefix_filter)) continue;
        }
        const stripped = file.name[0..file.name.len-4];
        const exe_name = if (!enable_target_suffix) stripped else b.fmt("{s}-{s}-{s}-{s}", 
            .{stripped, @tagName(target.result.cpu.arch), @tagName(target.result.abi), @tagName(target.result.os.tag)});
        const exe = b.addExecutable(
            .{
                .root_source_file = b.path(b.fmt("{s}/{s}", .{path, file.name})),
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
pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{});
    const opt = b.standardOptimizeOption(.{});

    const enable_gui = b.option(bool, "gui", "whether to enable the GUI w/ raylib") orelse false;

    const meta_opts = b.addOptions();
    meta_opts.addOption(bool, "enable_gui", enable_gui);

    const zynth = b.addModule("zynth", .{
        .root_source_file = b.path("src/zynth.zig"),
        .target = target,
        .optimize = opt,
        .link_libc = enable_gui,
    });
    if (enable_gui) {
        const rl = b.lazyDependency("raylib", .{.target = target, .optimize = opt}) orelse return;
        zynth.addIncludePath(rl.path("src"));
        zynth.linkLibrary(rl.artifact("raylib"));
    } else {
        zynth.addIncludePath(b.path("."));
        zynth.addCSourceFile(.{
            .file = b.path("miniaudio.h"),
            .language = .c,
            .flags = &.{"-DMINIAUDIO_IMPLEMENTATION", "-x", "c"},
        });
    }
    zynth.addOptions("MetaConfig", meta_opts);


    const preset = b.addModule("preset", .{
        .root_source_file = b.path("src/preset/preset.zig"),
        .target = target,
        .optimize = opt,
        .link_libc = enable_gui,
    });
    preset.addImport("zynth", zynth);

    const prefix_filter_opt = b.option([]const u8, "example-filter", "filter the the examples to build with the prefix of the provided strings.");
    const enable_target_suffix = b.option(bool, "enable-target-suffix", "Appends the target triple to the executable name, useful creating github releases.") orelse false;
    
    compile_dir(b, target, opt, "src/examples", enable_target_suffix, prefix_filter_opt, zynth, preset);
    if (enable_gui) compile_dir(b, target, opt, "src/examples/gui", enable_target_suffix, prefix_filter_opt, zynth, preset);

    const wasm_target = b.resolveTargetQuery(.{.cpu_arch = .wasm32});
    std.log.debug("wasm target {}", .{wasm_target});
    compile_dir(b, wasm_target, opt, "src/examples", enable_target_suffix, prefix_filter_opt, zynth, preset);


}
