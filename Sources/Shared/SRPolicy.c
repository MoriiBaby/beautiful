#include "SRPolicy.h"
#include <string.h>

static const char *SRSkipQualifiers(const char *s) {
    if (!s) return 0;
    while (*s && strchr("rnNoORV", *s)) ++s;
    return s;
}
static bool SRIsObject(const char *s) {
    if (!s || s[0] != '@') return false;
    if (s[1] == '\0') return true;
    // @? is a block, not an interchangeable plain object in this verifier.
    if (s[1] != '"') return false;
    const char *end = strchr(s + 2, '"');
    return end && end[1] == '\0';
}
bool SRTypeEncodingMatches(const char *actual, const char *expected) {
    actual = SRSkipQualifiers(actual); expected = SRSkipQualifiers(expected);
    if (!actual || !expected || !*actual || !*expected) return false;
    if (SRIsObject(actual) && SRIsObject(expected)) return true;
    return strcmp(actual, expected) == 0;
}
bool SRStickyFlagNext(bool previous, bool dictionaryPresent, bool keyPresent, bool value) {
    return dictionaryPresent && keyPresent ? value : previous;
}
bool SRKeyboardShouldResize(bool windowPresent, bool frontmostMatchesBundle) {
    return windowPresent && !frontmostMatchesBundle;
}
bool SRKeyboardShouldForwardBounds(bool mode169, bool hookScreen) {
    return mode169 && hookScreen;
}
SRKeyboardGeometry SRKeyboardGeometryForScreen(SRRect s) {
    SRKeyboardGeometry result = {s, s};
    if (s.width > s.height) {
        result.frame = (SRRect){(s.width - s.height) * 0.5, 0, s.height, s.height};
        result.bounds = (SRRect){0, 0, s.height, s.height};
    }
    return result;
}
