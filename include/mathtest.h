#pragma once

#include "example-static-lib.h"
#include <cstdint>

#ifdef __cplusplus
extern "C" {
#endif

// Zig library -------------------------
typedef struct Vec2 {
    int x, y;

#ifdef __cplusplus
    Vec2 add(Vec2) const;
#endif

} Vec2_t;

Vec2 Vec2_add(Vec2 first, Vec2 second);

int* testAlloc();

uint32_t useCLib(ExampleStaticStruct ess);
// ---------------------------------------

#ifdef __cplusplus
}

inline Vec2 Vec2::add(Vec2 v2) const {
    return Vec2_add(*this, v2);
}
#endif
