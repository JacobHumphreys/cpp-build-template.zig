#include <example-static-lib.h>
#include <example-dynamic-lib.hpp>
#include <mathtest.h>
#include <format>
#include <iostream>
#include <ostream>

int main() {
    ExampleDynamicStruct eds = {
        .message = "Hello Zig",
    };
    eds.sayMessage();

    ExampleStaticStruct ess {
        .value = 3,
    };
    std::cout << std::format("ExampleStaticStruct: {{{}, {}}}", useCLib(ess), getOne()) << std::endl;

    Vec2 x = { .x = 2, .y = 1 };
    x = x.add({ .x = 0, .y = 1 });
    std::cout << std::format("ExampleZigStruct: {{{}, {}}}", x.x, x.y) << std::endl;
    return 0;
}
