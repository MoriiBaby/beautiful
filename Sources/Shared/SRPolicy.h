#pragma once
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif
// Skip ObjC argument ownership/direction qualifiers, not pointer/struct/block types.
bool SRTypeEncodingMatches(const char *actual, const char *expected);
bool SRStickyFlagNext(bool previous, bool dictionaryPresent, bool keyPresent, bool value);
bool SRKeyboardShouldResize(bool windowPresent, bool frontmostMatchesBundle);
bool SRKeyboardShouldForwardBounds(bool mode169, bool hookScreen);
typedef struct { double x, y, width, height; } SRRect;
typedef struct { SRRect frame, bounds; } SRKeyboardGeometry;
SRKeyboardGeometry SRKeyboardGeometryForScreen(SRRect screen);
#ifdef __cplusplus
}
#endif
