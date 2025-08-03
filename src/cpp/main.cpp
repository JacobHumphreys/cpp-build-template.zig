#include "example-static-lib.h"
#include "mathtest.h"
#include <format>
#include <iostream>
#include <ostream>

int main() {
    ExampleStaticStruct ess {
        .value = 3,
    };
    std::cout << std::format("ExampleStaticStruct: {{{}}}", useCLib(ess)) << std::endl;

    Vec2 x = { .x = 2, .y = 1 };
    x = x.add({ .x = 0, .y = 1 });
    std::cout << std::format("ExmapleZigStruct: {{ {}, {} }}", x.x, x.y) << std::endl;
    return 0;
}
