#pragma once

#include "example-static-lib.h"
#include <cstdint>
extern "C" {
typedef struct Vec2 {
    int x, y;

    Vec2 add(Vec2) const;
} Vec2_t;

Vec2 Vec2_add(Vec2 first, Vec2 second);

int* testAlloc();

uint32_t useCLib(ExampleStaticStruct ess);
}

inline Vec2 Vec2::add(Vec2 v2) const {
    return Vec2_add(*this, v2);
}
