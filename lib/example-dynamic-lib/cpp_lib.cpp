#include <iostream>
#include <ostream>
#include <example-dynamic-lib.hpp>

void ExampleDynamicStruct::sayMessage() const {
    std::cout << message << std::endl;
}
