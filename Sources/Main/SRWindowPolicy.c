#include "SRWindowPolicy.h"
#include <math.h>
static bool finiteRect(SRWindowRect r) {
    return isfinite(r.x) && isfinite(r.y) && isfinite(r.width) && isfinite(r.height);
}
static double clamp(double x, double lo, double hi) { return fmin(fmax(x, lo), hi); }
bool SRWindowConstrain(SRWindowRect r, SRWindowRect screen, SRWindowRect *out) {
    if (!out || !finiteRect(r) || !finiteRect(screen) || screen.width <= 0 || screen.height <= 0 ||
        !isfinite(screen.x + screen.width) || !isfinite(screen.y + screen.height) ||
        r.width <= 0 || r.height <= 0) return false;
    double minW = fmin(160.0, screen.width), minH = fmin(200.0, screen.height);
    r.width = clamp(r.width, minW, screen.width);
    r.height = clamp(r.height, minH, screen.height);
    r.x = clamp(r.x, screen.x, screen.x + screen.width - r.width);
    r.y = clamp(r.y, screen.y, screen.y + screen.height - r.height);
    *out = r;
    return true;
}
bool SRWindowResize(SRWindowRect start, SRWindowRect screen, double scale, SRWindowRect *out) {
    if (!isfinite(scale) || scale <= 0) return false;
    SRWindowRect requested = start;
    requested.width *= scale; requested.height *= scale;
    return SRWindowConstrain(requested, screen, out);
}
