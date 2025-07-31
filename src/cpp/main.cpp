#include "mathtest.h"
#include "format"
#include <iostream>
#include <ostream>

int main() {
    Vec2 x = {.x = 1, .y = 2};
    x = x.add({1, 0});
    std::cout << std::format("{{{},{}}}", x.x, x.y) << std::endl;
    return 0;
}
