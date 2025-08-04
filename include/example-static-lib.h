#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint32_t value;
} ExampleStaticStruct;

int getOne();

#ifdef __cplusplus
}
#endif
