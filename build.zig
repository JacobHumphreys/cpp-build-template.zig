const std = @import("std");
const build_helpers = @import("build/build_helpers.zig");

const builtin = std.builtin;
const ArrayList = std.ArrayList;
const mem = std.mem;
const Allocator = mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const fs = std.fs;
const Build = std.Build;
const Module = Build.Module;
const CSourceLanguage = Module.CSourceLanguage;

const zcc = @import("compile_commands");

const additional_flags: []const []const u8 = &.{"-std=c++20"};
const debug_flags = runtime_check_flags ++ warning_flags;

const runtime_check_flags: []const []const u8 = &.{
    "-fsanitize=array-bounds,null,alignment,unreachable,address,leak", // asan and leak are linux/macos only in 0.14.1
    "-fstack-protector-strong",
    "-fno-omit-frame-pointer",
};

const warning_flags: []const []const u8 = &.{
    "-Wall",
    "-Wextra",
    "-Wnull-dereference",
    "-Wuninitialized",
    "-Wshadow",
    "-Wpointer-arith",
    "-Wstrict-aliasing",
    "-Wstrict-overflow=5",
    "-Wcast-align",
    "-Wconversion",
    "-Wsign-conversion",
    "-Wfloat-equal",
    "-Wformat=2",
    "-Wswitch-enum",
    "-Wmissing-declarations",
    "-Wunused",
    "-Wundef",
    "-Werror",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.addModule("exe", .{
        .target = target,
        .optimize = optimize,
        .link_libcpp = true, // May need to change this to linkLibC() for your project
    });

    const exe = b.addExecutable(.{
        .name = "zig-compiled",
        .root_module = exe_mod,
    });

    const debug_mod = b.addModule("debug", .{
        .target = target,
        .optimize = optimize,
        .link_libcpp = true, // May need to change this to linkLibC() for your project
    });
    // Does not link asan or use build flags other than "std="
    const debug = b.addExecutable(.{
        .name = "debug",
        .root_module = debug_mod,
        .use_llvm = true,
    });

    const exe_flags = getBuildFlags(
        b.allocator,
        exe,
        optimize,
    ) catch |err|
        @panic(@errorName(err));

    const exe_files = build_helpers.getCSrcFiles(
        b.allocator,
        .{
            .dir_path = "src/cpp",
            .flags = exe_flags,
            .language = .cpp,
        },
    ) catch |err|
        @panic(@errorName(err));

    // Setup exe executable
    {
        exe.addCSourceFiles(exe_files);
        exe.addIncludePath(b.path("include"));
    }

    // Setup debug executable
    {
        var debug_files = exe_files;
        debug_files.flags = additional_flags;
        debug.addCSourceFiles(debug_files);
        debug.addIncludePath(b.path("include"));
    }

    // Build and Link zig -> c code -------------------------------------------

    // This is not included in the install step
    const zig_lib = b.addLibrary(.{
        .name = "mathtest",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zig/mathtest.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });
    zig_lib.linkLibC();
    zig_lib.addIncludePath(b.path("include/"));
    exe.root_module.linkLibrary(zig_lib);
    debug.root_module.linkLibrary(zig_lib);
    //-------------------------------------------------------------------------

    // Build and/or Link Dynamic library --------------------------------------
    const dynamic_option = b.option(bool, "build-dynamic", "builds the static.a file") orelse false;
    if (dynamic_option) {
        const dynamic_lib = build_helpers.addCLib(b, .{
            .name = "example_dynamic",
            .dir_path = "lib/example-dynamic-lib/",
            .optimize = optimize,
            .target = target,
            .flags = additional_flags ++ debug_flags ++ warning_flags,
            .language = .cpp,
            .linkage = .dynamic,
        });
        exe.root_module.linkLibrary(dynamic_lib);
        debug.root_module.linkLibrary(dynamic_lib);
        b.installArtifact(dynamic_lib);
    } else {
        exe.root_module.addLibraryPath(b.path("lib/"));
        exe.root_module.linkSystemLibrary("example_dynamic", .{});
        debug.root_module.addLibraryPath(b.path("lib/"));
        debug.root_module.linkSystemLibrary("example_dynamic", .{});
    }
    //-------------------------------------------------------------------------

    // Build and/or Link Static library --------------------------------------
    const static_option = b.option(bool, "build-static", "builds the static.a file") orelse false;
    if (static_option) {
        const static_lib = build_helpers.addCLib(b, .{
            .name = "example_static",
            .dir_path = "lib/example-static-lib/",
            .optimize = optimize,
            .target = target,
            .language = .c,
            .linkage = .static,
        });
        exe.linkLibrary(static_lib);
        debug.linkLibrary(static_lib);
        zig_lib.linkLibrary(static_lib);
        b.installArtifact(static_lib);
    } else {
        exe.addLibraryPath(b.path("lib/"));
        exe.linkSystemLibrary("example_static");
        debug.addLibraryPath(b.path("lib/"));
        debug.linkSystemLibrary("example_static");
    }
    //-------------------------------------------------------------------------

    b.installArtifact(exe);
    const exe_run = b.addRunArtifact(exe);
    const debug_run = b.addRunArtifact(debug);

    exe_run.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        exe_run.addArgs(args);
        debug_run.addArgs(args);
    }

    const run_step = b.step("run", "runs the application");
    run_step.dependOn(&exe_run.step);

    const debug_step = b.step("debug", "runs the applicaiton without any warning or san flags");

    // Causes debug to only be compiled when using debug step.
    debug_step.dependOn(&b.addInstallArtifact(debug, .{}).step);

    var targets = ArrayList(*std.Build.Step.Compile).empty;
    defer targets.deinit(b.allocator);

    targets.append(b.allocator, exe) catch |err| @panic(@errorName(err));
    targets.append(b.allocator, debug) catch |err| @panic(@errorName(err));

    // Used to generate compile_commands.json
    _ = zcc.createStep(
        b,
        "cmds",
        targets.toOwnedSlice(b.allocator) catch |err|
            @panic(@errorName(err)),
    );
}

/// Returns the build flags used depending on optimization level.
/// Will automatically link asan to exe if debug mode is used.
fn getBuildFlags(
    alloc: Allocator,
    exe: *std.Build.Step.Compile,
    optimize: std.builtin.OptimizeMode,
) ![]const []const u8 {
    var flags: []const []const u8 = undefined;

    if (optimize == .Debug) {
        flags = additional_flags ++ debug_flags;
        if (exe.rootModuleTarget().os.tag == .windows)
            return flags;

        exe.root_module.addLibraryPath(.{ .cwd_relative = try build_helpers.getClangPath(alloc, exe.rootModuleTarget()) });
        const asan_lib = if (exe.rootModuleTarget().os.tag == .windows) "clang_rt.asan_dynamic-x86_64" // Won't be triggered in current version
            else "clang_rt.asan-x86_64";

        exe.linkSystemLibrary(asan_lib);
    } else {
        flags = additional_flags;
    }
    return flags;
}
