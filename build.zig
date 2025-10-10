const std = @import("std");
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

    const exe_files = getCSrcFiles(
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
        const dynamic_lib = createCLib(b, .{
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
        const static_lib = createCLib(b, .{
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

/// Used to recursively fetch source files from a directory
pub fn getCSrcFiles(
    alloc: std.mem.Allocator,
    opts: struct {
        dir_path: []const u8 = "./src/",
        language: CSourceLanguage,
        flags: []const []const u8 = &.{},
    },
) !Module.AddCSourceFilesOptions {
    const src = try fs.cwd().openDir(opts.dir_path, .{ .iterate = true });

    var file_list = ArrayList([]const u8).empty;
    errdefer file_list.deinit(alloc);

    const extension = @tagName(opts.language); // Will break for obj-c and assembly

    var src_iterator = src.iterate();
    while (try src_iterator.next()) |entry| {
        switch (entry.kind) {
            .file => {
                if (!mem.endsWith(u8, entry.name, extension))
                    continue;

                const path = try fs.path.join(alloc, &.{ opts.dir_path, entry.name });

                try file_list.append(alloc, path);
            },
            .directory => {
                var dir_opts = opts;
                dir_opts.dir_path = try fs.path.join(alloc, &.{ opts.dir_path, entry.name });

                try file_list.appendSlice(alloc, (try getCSrcFiles(alloc, dir_opts)).files);
            },
            else => continue,
        }
    }

    return Module.AddCSourceFilesOptions{
        .files = try file_list.toOwnedSlice(alloc),
        .language = opts.language,
        .flags = opts.flags,
    };
}

/// Returns the path of the system installation of clang sanitizers
fn getClangPath(alloc: std.mem.Allocator, target: std.Target) ![]const u8 {
    const asan_lib = if (target.os.tag == .windows) "clang_rt.asan_dynamic-x86_64.dll" else "libclang_rt.asan-x86_64.so";
    var child_proc = std.process.Child.init(&.{
        "clang",
        try std.mem.concat(alloc, u8, &.{ "-print-file-name=", asan_lib }),
    }, alloc);
    child_proc.stdout_behavior = .Pipe;

    try child_proc.spawn();

    const reader_buff: []u8 = try alloc.alloc(u8, 512);
    var child_stdout_reader = child_proc.stdout.?.reader(reader_buff);
    const child_stdout = &child_stdout_reader.interface;

    var output = try child_stdout.takeDelimiterExclusive('\n');

    _ = try child_proc.wait();

    const file_delim = if (target.os.tag == .windows) "\\" else "/";

    if (mem.lastIndexOf(u8, output, file_delim)) |last_path_sep| {
        output.len = last_path_sep + 1;
    } else {
        @panic("Path Not Formatted Correctly");
    }
    return output;
}

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

/// Returns the build flags used depending on optimization level.
/// Will automatically link asan to exe if debug mode is used.
fn getBuildFlags(
    alloc: Allocator,
    exe: *std.Build.Step.Compile,
    optimize: std.builtin.OptimizeMode,
) ![]const []const u8 {
    var cpp_flags: []const []const u8 = undefined;

    if (optimize == .Debug) {
        cpp_flags = additional_flags ++ debug_flags;
        if (exe.rootModuleTarget().os.tag == .windows)
            return cpp_flags;

        exe.addLibraryPath(.{ .cwd_relative = try getClangPath(alloc, exe.rootModuleTarget()) });
        const asan_lib = if (exe.rootModuleTarget().os.tag == .windows) "clang_rt.asan_dynamic-x86_64" // Won't be triggered in current version
            else "clang_rt.asan-x86_64";

        exe.linkSystemLibrary(asan_lib);
    } else {
        cpp_flags = additional_flags;
    }
    return cpp_flags;
}

/// Creates a C library.
fn createCLib(
    b: *Build,
    lib_options: struct {
        name: []const u8,
        dir_path: []const u8,
        language: CSourceLanguage,
        include_path: []const u8 = "include/",
        linkage: builtin.LinkMode,
        optimize: builtin.OptimizeMode,
        target: Build.ResolvedTarget,
        flags: []const []const u8 = &.{},
    },
) *Build.Step.Compile {
    var lib = b.addLibrary(.{
        .name = lib_options.name,
        .root_module = b.createModule(.{
            .optimize = lib_options.optimize,
            .target = lib_options.target,
            .link_libc = lib_options.language == .c,
            .link_libcpp = lib_options.language == .cpp,
        }),
        .linkage = lib_options.linkage,
    });

    lib.addCSourceFiles(
        getCSrcFiles(b.allocator, .{
            .dir_path = lib_options.dir_path,
            .language = lib_options.language,
            .flags = lib_options.flags,
        }) catch |err|
            @panic(@errorName(err)),
    );

    lib.addIncludePath(b.path(lib_options.include_path));

    return lib;
}
