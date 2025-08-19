const std = @import("std");

fn compile_dir(
    b: *std.Build,
    step: *std.Build.Step,
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
        const mod = b.addModule(file.name, .{
            .root_source_file = b.path(b.fmt("{s}/{s}", .{path, file.name})),
            .target = target,
            .optimize = opt,
        });
        const exe = b.addExecutable(
            .{
                .root_module = mod,
                .name = exe_name,
            }
        );
        exe.root_module.addImport("zynth", zynth);
        exe.root_module.addImport("preset", preset);
        const arti = b.addInstallArtifact(exe, .{});
        step.dependOn(&arti.step);
    }
}
pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
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
    const ma = b.addTranslateC(.{
        .optimize = opt,
        .target = target,
        .root_source_file = b.path("miniaudio.h"),
    });
    
    const ma_mod = ma.createModule();
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
        zynth.addImport("c", ma_mod);
    }
    // zynth.addOptions("MetaConfig", meta_opts);


    const preset = b.addModule("preset", .{
        .root_source_file = b.path("src/preset/preset.zig"),
        .target = target,
        .optimize = opt,
        .link_libc = enable_gui,
    });
    preset.addImport("zynth", zynth);
    if (target.result.cpu.arch.isWasm()) {
        if (b.sysroot == null) {
            @panic("Pass '--sysroot \"$EMSDK/upstream/emscripten\"'");
        }

        const cache_include = std.fs.path.join(b.allocator, &.{ b.sysroot.?, "cache", "sysroot", "include" }) catch @panic("Out of memory");
        defer b.allocator.free(cache_include);

        var dir = std.fs.openDirAbsolute(cache_include, .{ .access_sub_paths = true, .no_follow = true }) catch @panic("No emscripten cache. Generate it!");
        dir.close();

        ma.addIncludePath(.{ .cwd_relative = cache_include });
        const wasm = b.addLibrary(.{
            .root_module = zynth,
            .linkage = .static,
            .name = "zynth"
        });
        wasm.addIncludePath(.{ .cwd_relative = cache_include });

        b.installArtifact(wasm);
        for (wasm.getCompileDependencies(false)) |lib| {
            if (lib.isStaticLibrary()) {
                std.log.debug("{s}", .{lib.name});
                // emcc.addArtifactArg(lib);
            }
        }
    }

    const prefix_filter_opt = b.option([]const u8, "example-filter", "filter the the examples to build with the prefix of the provided strings.");
    const enable_target_suffix = b.option(bool, "enable-target-suffix", "Appends the target triple to the executable name, useful creating github releases.") orelse false;

    const example_step = b.step("examples", "build and install the examples");

    compile_dir(b, example_step, target, opt, "src/examples", enable_target_suffix, prefix_filter_opt, zynth, preset);
    if (enable_gui) compile_dir(b, example_step, target, opt, "src/examples/gui", enable_target_suffix, prefix_filter_opt, zynth, preset);


    //     const wasm_target = b.resolveTargetQuery(.{.cpu_arch = .wasm32, .os_tag = .emscripten});
    //     std.log.debug("wasm target {}", .{wasm_target});
    // 
    //     const zynth_wasm = b.addModule("zynth", .{
    //         .root_source_file = b.path("src/wasm_demo.zig"),
    //         .target = target,
    //         .optimize = opt,
    //         .link_libc = enable_gui,
    //     });

    //     const activate_emsdk_step = @import("zemscripten").activateEmsdkStep(b);
    // 
    //     const zemscripten = b.dependency("zemscripten", .{});
    //     wasm.root_module.addImport("zemscripten", zemscripten.module("root"));
    // 
    //     const emcc_flags = @import("zemscripten").emccDefaultFlags(b.allocator, .{
    //         .optimize = opt,
    //         .fsanitize = false,
    //     });
    //     
    //     var emcc_settings = @import("zemscripten").emccDefaultSettings(b.allocator, .{
    //         .optimize = opt,
    //     });
    // 
    //     try emcc_settings.put("ALLOW_MEMORY_GROWTH", "1");
    // 
    //     const emcc_step = @import("zemscripten").emccStep(
    //         b,
    //         wasm,
    //         .{
    //             .optimize = opt,
    //             .flags = emcc_flags,
    //             .settings = emcc_settings,
    //             .use_preload_plugins = true,
    //             .embed_paths = &.{},
    //             .preload_paths = &.{},
    //             .install_dir = .{ .custom = "web" },
    //         },
    //     );
    //     emcc_step.dependOn(activate_emsdk_step);
    // 
    //     b.getInstallStep().dependOn(emcc_step);
    //     //compile_dir(b, wasm_target, opt, "src/examples", enable_target_suffix, prefix_filter_opt, zynth, preset);
    //     
    //     const html_filename = try std.fmt.allocPrint(b.allocator, "{s}.html", .{wasm.name});
    // 
    //     const emrun_args = .{};
    //     const emrun_step = @import("zemscripten").emrunStep(
    //         b,
    //         b.getInstallPath(.{ .custom = "web" }, html_filename),
    //         &emrun_args,
    //     );
    // 
    //     emrun_step.dependOn(emcc_step);
    // 
    //     b.step("emrun", "Build and open the web app locally using emrun").dependOn(emrun_step);
    // 
}
