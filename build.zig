const std = @import("std");

fn compile_dir_wasm(b: *std.Build,
    step: *std.Build.Step,
    opt: std.builtin.OptimizeMode,
    path: []const u8,
    enable_target_suffix: bool,
    prefix_filter_opt: ?[]const u8,
    zynth: *std.Build.Module,
    preset: *std.Build.Module) !void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .cpu_model = .{ .explicit = &std.Target.wasm.cpu.mvp },
        .cpu_features_add = std.Target.wasm.featureSet(&.{
            .atomics,
            .bulk_memory,
        }),
        .os_tag = .emscripten,
    });

    var dir = b.path(path).getPath3(b, null).openDir(".", .{.iterate = true }) catch unreachable;
    defer dir.close();
    var it = dir.iterate();
    var first = true;
    var wasm_manifest = std.io.Writer.Allocating.init(b.allocator);
    try wasm_manifest.writer.writeByte('[');
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
        mod.addImport("zynth", zynth);
        mod.addImport("preset", preset);

        const wasm_module = b.addLibrary(.{
            .linkage = .static,
            .root_module = mod,
            .name = exe_name
        });
        wasm_module.linkLibC();
        // wasm.addIncludePath(.{ .cwd_relative = cache_include });
        wasm_module.entry = .disabled; // for some reason it still export main in the std/start.zig ?? and this does not help anything
        wasm_module.rdynamic = true;
        wasm_module.bundle_ubsan_rt = false;
        wasm_module.bundle_compiler_rt = false;

        //
        // run emcc on the static lib, and install the generated *.mjs and *.wasm
        //
        const arti = b.addInstallArtifact(wasm_module, .{});
        // step.dependOn(&arti.step);
        const emcc = b.addSystemCommand(&.{"emcc", "-sMODULARIZE=1", "-sEXPORT_ES6=1", "-Oz"});
        emcc.addArtifactArg(wasm_module);
        emcc.addArg("-o");
        const wasm = emcc.addOutputFileArg(b.fmt("{s}.mjs", .{exe_name}));

        const install_wasm = b.addInstallDirectory(.{
            .source_dir = wasm.dirname(),
            .install_dir = .{ .custom = "web" },
            .install_subdir = ".",
        });

        install_wasm.step.dependOn(&arti.step);
        emcc.step.dependOn(&arti.step);
        step.dependOn(&emcc.step);
        step.dependOn(&install_wasm.step);

        
        if (first) try wasm_manifest.writer.print("\"{s}\"", .{exe_name})
        else try wasm_manifest.writer.print(", \"{s}\"", .{exe_name});

        first = false;
    }
    try wasm_manifest.writer.writeByte(']');
    const wf = b.addWriteFiles();
    const manifest_path = wf.add("manifest", try wasm_manifest.toOwnedSlice());
    const install_manifest = b.addInstallFile(manifest_path, "web/manifest.json");
    step.dependOn(&install_manifest.step);

    // also put index html into the zig-out/web/
    const install_index = b.addInstallFile(b.path("web/index.html"), "web/index.html");
    step.dependOn(&install_index.step);
    const install_ico = b.addInstallFile(b.path("web/favicon.ico"), "web/favicon.ico");
    step.dependOn(&install_ico.step);


}

fn compile_dir(
    b: *std.Build,
    step: *std.Build.Step,
    target: std.Build.ResolvedTarget, 
    opt: std.builtin.OptimizeMode,
    path: []const u8,
    enable_target_suffix: bool,
    prefix_filter_opt: ?[]const u8,
    zynth: *std.Build.Module,
    preset: *std.Build.Module) !void {

    if (target.result.cpu.arch.isWasm()) return compile_dir_wasm(b, step, opt, path, enable_target_suffix, prefix_filter_opt, zynth, preset);
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
        mod.addImport("zynth", zynth);
        mod.addImport("preset", preset);


        const exe = b.addExecutable(
            .{
                .root_module = mod,
                .name = exe_name,
            }
        );
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
        .link_libc = true,
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
        zynth.addIncludePath(.{ .cwd_relative = cache_include });

        const zemscripten = b.dependency("zemscripten", .{});
        zynth.addImport("zemscripten", zemscripten.module("root"));
    }

    const prefix_filter_opt = b.option([]const u8, "example-filter", "filter the the examples to build with the prefix of the provided strings.");
    const enable_target_suffix = b.option(bool, "enable-target-suffix", "Appends the target triple to the executable name, useful creating github releases.") orelse false;

    const example_step = b.step("examples", "build and install the examples");

    try compile_dir(b, example_step, target, opt, "src/examples", enable_target_suffix, prefix_filter_opt, zynth, preset);
    if (enable_gui) try compile_dir(b, example_step, target, opt, "src/examples/gui", enable_target_suffix, prefix_filter_opt, zynth, preset);


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
