#pragma once

extern "C" {

typedef struct Vec2 {
    int x, y;
    Vec2 add(Vec2) const;
} Vec2_t;

Vec2_t Vec2_add(Vec2_t first, Vec2_t second);

int* testAlloc();
}

inline Vec2 Vec2::add(Vec2 v2) const {
    return Vec2_add(*this, v2);
}
