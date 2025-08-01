#include "mathtest.h"
#include <format>
#include <iostream>
#include <ostream>

int main() {
    Vec2 x = {.x=2,.y = 1};
    x = x.add({.x = 0, .y = 1});
    std::cout << std::format("{{ {},{} }}", x.x, x.y) << std::endl;
    return 0;
}
