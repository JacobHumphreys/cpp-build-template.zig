const std = @import("std");
const builtin = std.builtin;
const ArrayList = std.ArrayList;
const mem = std.mem;
const fs = std.fs;
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

/// Returns the path of the system installation of clang sanitizers
pub fn getClangPath(alloc: std.mem.Allocator, target: std.Target) ![]const u8 {
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
pub fn addCLib(
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
