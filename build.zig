const std = @import("std");
const ArrayList = std.ArrayListUnmanaged;
const mem = std.mem;
const Allocator = mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const fs = std.fs;
const Module = std.Build.Module;

const zcc = @import("compile_commands");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "main",
        .target = target,
        .optimize = optimize,
    });

    const debug = b.addExecutable(.{
        .name = "debug",
        .target = target,
        .optimize = optimize,
    });

    const cpp_files = getSrcFiles(
        b.allocator,
        "src/",
        "cpp",
    ) catch |err|
        @panic(@errorName(err));

    const cpp_flags = getBuildFlags(
        b.allocator,
        exe,
        optimize,
    ) catch |err|
        @panic(@errorName(err));

    exe.addCSourceFiles(
        Module.AddCSourceFilesOptions{
            .files = cpp_files,
            .flags = cpp_flags,
            .language = .cpp,
        },
    );

    debug.addCSourceFiles(
        Module.AddCSourceFilesOptions{
            .files = cpp_files,
            .flags = additional_flags,
            .language = .cpp,
        },
    );

    exe.linkLibCpp();
    debug.linkLibCpp();

    exe.addIncludePath(b.path("include/"));
    debug.addIncludePath(b.path("include/"));

    //Build and Link zig -> c code --------------------------------
    const lib = b.addSharedLibrary(.{
        .name = "mathtest",
        .root_source_file = b.path("src/zig/mathtest.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC();
    exe.linkLibrary(lib);
    debug.linkLibrary(lib);
    //---------------------------------------------

    b.installArtifact(exe);
    b.installArtifact(debug);
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
    debug_step.dependOn(&debug_run.step);

    var targets = ArrayList(*std.Build.Step.Compile).empty;
    defer targets.deinit(b.allocator);

    targets.append(b.allocator, exe) catch |err| @panic(@errorName(err));
    targets.append(b.allocator, debug) catch |err| @panic(@errorName(err));

    _ = zcc.createStep(
        b,
        "cmds",
        targets.toOwnedSlice(b.allocator) catch |err|
            @panic(@errorName(err)),
    );
}

pub fn getSrcFiles(alloc: Allocator, dir_path: []const u8, extension: []const u8) ![]const []const u8 {
    const src = try fs.cwd().openDir(dir_path, .{ .iterate = true });

    var file_list = ArrayList([]const u8).empty;
    errdefer file_list.deinit(alloc);

    var src_iterator = src.iterate();
    while (try src_iterator.next()) |entry| {
        switch (entry.kind) {
            .file => {
                if (!mem.endsWith(u8, entry.name, extension))
                    continue;

                const path = try fs.path.join(alloc, &.{ dir_path, entry.name });

                try file_list.append(alloc, path);
            },
            .directory => {
                const path = try fs.path.join(alloc, &.{ dir_path, entry.name });
                try file_list.appendSlice(alloc, try getSrcFiles(alloc, path, extension));
            },
            else => continue,
        }
    }

    return try file_list.toOwnedSlice(alloc);
}

fn getClangPath(alloc: Allocator) ![]const u8 {
    const Child = std.process.Child;
    var child_proc = Child.init(&.{
        "clang",
        "-print-file-name=libclang_rt.asan-x86_64.so",
    }, alloc);
    child_proc.stdout_behavior = .Pipe;

    const read_buffer = try alloc.alloc(u8, 512);
    defer alloc.free(read_buffer);

    try child_proc.spawn();

    const child_std_out = child_proc.stdout.?;

    var output_size = try child_std_out.readAll(read_buffer);

    _ = try child_proc.wait();

    if (mem.lastIndexOf(u8, read_buffer[0..output_size], "/")) |last_path_sep| {
        output_size = last_path_sep + 1;
    } else {
        @panic("Path Not Formatted Correctly");
    }

    const output_buffer = try alloc.alloc(u8, output_size);
    @memcpy(output_buffer, read_buffer[0..output_size]);
    return output_buffer;
}

const additional_flags: []const []const u8 = &.{"-std=c++20"};

const debug_flags = runtime_check_flags ++ warning_flags;

const runtime_check_flags: []const []const u8 = &.{
    "-fsanitize=address,array-bounds,null,alignment,leak,unreachable",
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

fn getBuildFlags(
    alloc: Allocator,
    exe: *std.Build.Step.Compile,
    optimize: std.builtin.OptimizeMode,
) ![]const []const u8 {
    var cpp_flags: []const []const u8 = undefined;

    if (optimize == .Debug or optimize == .ReleaseSafe) {
        cpp_flags = additional_flags ++ debug_flags;
        exe.addLibraryPath(.{ .cwd_relative = try getClangPath(alloc) });
        exe.linkSystemLibrary("clang_rt.asan-x86_64");
        exe.linkSystemLibrary("clang_rt.ubsan_standalone-x86_64");
    } else {
        cpp_flags = additional_flags;
    }
    return cpp_flags;
}
