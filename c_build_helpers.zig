const std = @import("std");
const builtin = std.builtin;
const fs = std.fs;
const ArrayList = std.ArrayList;
const mem = std.mem;
const Allocator = mem.Allocator;
const Build = std.Build;
const Module = Build.Module;
const CSourceLanguage = Module.CSourceLanguage;

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

/// Returns the build flags used depending on optimization level.
/// Will automatically link asan to exe if debug mode is used.
///
/// Returned value is owned memory
pub fn getBuildFlags(
    alloc: Allocator,
    exe: *std.Build.Step.Compile,
    optimize: std.builtin.OptimizeMode,
    opts: struct {
        /// Flags for all release modes
        global_flags: []const []const u8 = &.{},
        /// Flags for debug release mode
        debug_flags: []const []const u8 = &.{},
        /// Specifies whether the asan library should be linked. Ignored on Windows due
        /// to lack of support
        link_asan: bool = true,
    },
) ![]const []const u8 {
    if (optimize == .Debug) {
        const cpp_flags = try std.mem.concat(alloc, []const u8, &.{ opts.global_flags, opts.debug_flags });

        if (exe.rootModuleTarget().os.tag == .windows) return cpp_flags;
        if (!opts.link_asan) return cpp_flags;

        exe.addLibraryPath(.{ .cwd_relative = try getClangPath(alloc, exe.rootModuleTarget()) });

        // Won't be triggered in current version
        const asan_lib = if (exe.rootModuleTarget().os.tag == .windows) "clang_rt.asan_dynamic-x86_64" else "clang_rt.asan-x86_64";

        exe.linkSystemLibrary(asan_lib);

        return cpp_flags;
    } else {
        return alloc.dupe([]const u8, opts.global_flags);
    }
    unreachable;
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

/// Creates a C library.
pub fn createCLib(
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

/// Because certain ides (CLION) wont find system headers on nix unless specifically pointed to.
///
/// Uses pkg-config to determine paths
pub fn addSystemLibIncludeFlags(b: *Build, module: *Module, libName: []const u8) !void {
    var child_arena = std.heap.ArenaAllocator.init(b.allocator);
    defer child_arena.deinit();
    const alloc = child_arena.allocator();

    var child_proc = std.process.Child.init(&.{ "pkg-config", "--cflags-only-I", libName }, alloc);
    child_proc.stdout_behavior = .Pipe;

    try child_proc.spawn();
    defer _ = child_proc.wait() catch {};

    var proc_output_buffer = ArrayList(u8).empty;

    while (true) {
        var tmp: [1024]u8 = undefined;
        const read_len = try child_proc.stdout.?.read(&tmp);
        if (read_len == 0) break;
        try proc_output_buffer.appendSlice(alloc, tmp[0..read_len]);
    }

    var path_iter = std.mem.splitScalar(u8, proc_output_buffer.items, ' ');

    while (path_iter.next()) |path| {
        const index = mem.indexOf(u8, path, "-I") orelse continue;
        if (index != 0) continue;

        const trimmed_path = Build.LazyPath{
            .cwd_relative = try removeAllAlloc(alloc, u8, path[2..], &std.ascii.whitespace),
        };
        //b.path(path[2..]);
        module.addIncludePath(trimmed_path);
    }
}

fn removeAllAlloc(alloc: Allocator, comptime T: type, haystack: []const T, needles: []const T) ![]T {
    var trimmed = try ArrayList(T).initCapacity(alloc, haystack.len);
    for (haystack) |elem| {
        if (std.mem.containsAtLeast(T, needles, 1, &.{elem})) continue;
        trimmed.appendAssumeCapacity(elem);
    }
    return try trimmed.toOwnedSlice(alloc);
}
