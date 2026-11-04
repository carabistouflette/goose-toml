// SPDX-License-Identifier: Apache-2.0
#include <stdint.h>

// Compiled as a separate translation unit without LTO. The Goose compiler
// cannot discard parsing or hoist this observable per-iteration consumption.
int64_t compare_consume(int64_t value) {
    __asm__ volatile("" : "+r"(value) : : "memory");
    return value;
}
