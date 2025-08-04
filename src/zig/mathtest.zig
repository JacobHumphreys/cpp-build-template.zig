const std = @import("std");
const Allocator = std.mem.Allocator;
const c_alloc = std.heap.c_allocator;
const c = @cImport({
    @cInclude("example-static-lib.h");
});

const Vec2 = extern struct {
    x: i32,
    y: i32,

    fn add(self: Vec2, other: Vec2) Vec2 {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }
};

export fn Vec2_add(a: Vec2, b: Vec2) Vec2 {
    return a.add(b);
}

const Error = error{
    ValueTooLowError,
};

export fn testAlloc() ?*i32 {
    var output: ?*Vec2 = value: {
        break :value doSomething(c_alloc, 3) catch |err| {
            std.debug.print("{s}\n", .{@errorName(err)});
            break :value null;
        };
    };

    if (output != null) c_alloc.destroy(output.?);

    output = value: {
        break :value doSomething(c_alloc, 10) catch |err| {
            std.debug.print("{s}\n", .{@errorName(err)});
            break :value null;
        };
    };

    const i = c_alloc.create(i32) catch {
        @panic("C allocation could not be done");
    };

    i.* = output.?.x;

    c_alloc.destroy(output.?);

    return i;
}

export fn useCLib(ess: c.ExampleStaticStruct) u32 {
    std.debug.print("useCLib output: {}\n", .{c.getOne()});
    return ess.value;
}

/// Returns owned memory
fn doSomething(alloc: Allocator, value: i32) (Allocator.Error || Error)!*Vec2 {
    if (value < 5)
        return Error.ValueTooLowError;
    const output = try alloc.create(Vec2);
    output.* = Vec2{ .x = value, .y = value - 5 };
    return output;
}
