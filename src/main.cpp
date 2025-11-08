
#include "example-dynamic-lib.hpp"
#include "example-static-lib.h"
#include <iostream>
#include <ostream>

int main() {
    ExampleDynamicStruct dynamic("hello zig");
    dynamic.sayMessage();
    ExampleStaticStruct static_struct(5);
    std::cout << static_struct.value << std::endl;
    return 0;
}
