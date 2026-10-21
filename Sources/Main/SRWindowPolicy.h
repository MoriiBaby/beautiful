#pragma once
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct { double x, y, width, height; } SRWindowRect;
// Validates finite, positive screen geometry and returns a fully on-screen frame.
// Tiny screens reduce minimums instead of producing impossible negative clamp ranges.
bool SRWindowConstrain(SRWindowRect requested, SRWindowRect screen, SRWindowRect *result);
bool SRWindowResize(SRWindowRect start, SRWindowRect screen, double scale, SRWindowRect *result);
#ifdef __cplusplus
}
#endif
