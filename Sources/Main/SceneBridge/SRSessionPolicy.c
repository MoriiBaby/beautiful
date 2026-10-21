#include "SRSessionPolicy.h"
#include <math.h>
#include <string.h>

static bool interval(double now, double timeout) {
    return isfinite(now) && now >= 0 && isfinite(timeout) &&
           timeout >= 0.05 && timeout <= 30.0 && isfinite(now + timeout);
}
static bool active(SRSessionPhase phase) {
    return phase >= SRSessionAcquiring && phase <= SRSessionAttached;
}
void SRSessionPolicyInit(SRSessionPolicy *p) {
    if (p) memset(p, 0, sizeof(*p));
}
bool SRSessionPolicyBegin(SRSessionPolicy *p, double now, double timeout) {
    if (!p || p->phase != SRSessionIdle || !interval(now, timeout) ||
        p->generation == UINT64_MAX) return false;
    ++p->generation;
    p->deadline = now + timeout;
    p->phase = SRSessionAcquiring;
    return true;
}
bool SRSessionPolicyAccept(const SRSessionPolicy *p, uint64_t generation) {
    return p && active(p->phase) && generation == p->generation;
}
bool SRSessionPolicyExpired(const SRSessionPolicy *p, double now) {
    return p && isfinite(now) && p->phase != SRSessionIdle &&
           p->phase != SRSessionAttached && p->phase != SRSessionClosed &&
           now >= p->deadline;
}
SRSessionSelection SRSessionPolicySelect(size_t matches, bool same_identity) {
    if (matches == 0) return SRSessionSelectionWait;
    if (matches > 1) return SRSessionSelectionAmbiguous;
    return same_identity ? SRSessionSelectionUnique : SRSessionSelectionStale;
}
bool SRSessionPolicyMayMutate(bool identity, bool known, bool frontmost,
                             bool restoring, bool owns_change) {
    return identity && known && !frontmost && (!restoring || owns_change);
}
bool SRSessionPolicyAcquired(SRSessionPolicy *p, uint64_t g,
                             bool foreground, bool proof) {
    if (!SRSessionPolicyAccept(p, g) || p->phase != SRSessionAcquiring ||
        (!foreground && !proof)) return false;
    if (foreground) {
        p->phase = SRSessionWaitingLayers;
    } else {
        p->phase = SRSessionActivating;
        p->foreground = SRSessionForegroundPending;
        p->pending_generation = g;
    }
    return true;
}
bool SRSessionPolicyExpectsCallback(const SRSessionPolicy *p, uint64_t g, bool restore) {
    if (!p || p->pending_generation != g) return false;
    if (restore) return p->phase == SRSessionClosing && p->generation == g &&
                        p->foreground == SRSessionRestorePending;
    return (p->phase == SRSessionActivating || p->phase == SRSessionClosing) &&
            p->foreground == SRSessionForegroundPending;
}
bool SRSessionPolicyCompleteForeground(SRSessionPolicy *p, uint64_t g,
                                       bool restore, bool confirmed) {
    if (!SRSessionPolicyExpectsCallback(p, g, restore)) return false;
    p->pending_generation = 0;
    p->foreground = !confirmed ? SRSessionForegroundUnresolved :
                    restore ? SRSessionForegroundRestored : SRSessionForegroundOwned;
    if (confirmed && !restore && p->phase == SRSessionActivating && p->generation == g)
        p->phase = SRSessionWaitingLayers;
    return true;
}
bool SRSessionPolicyAttach(SRSessionPolicy *p, uint64_t g) {
    if (!SRSessionPolicyAccept(p, g) || p->phase != SRSessionWaitingLayers) return false;
    p->phase = SRSessionAttached;
    return true;
}
bool SRSessionPolicyBeginClose(SRSessionPolicy *p, double now, double timeout) {
    if (!p || p->phase == SRSessionClosing || p->phase == SRSessionClosed ||
        !interval(now, timeout)) return false;
    /* Saturate rather than wrap: terminal phase guards also reject callbacks. */
    if (p->generation != UINT64_MAX) ++p->generation;
    p->phase = SRSessionClosing;
    p->deadline = now + timeout;
    return true;
}
SRSessionRollback SRSessionPolicyRollback(const SRSessionPolicy *p, double now,
                                          bool identity, bool foreground, bool proof) {
    if (!p || p->phase != SRSessionClosing) return SRSessionRollbackUnresolved;
    switch (p->foreground) {
        case SRSessionForegroundUntouched:
        case SRSessionForegroundRestored: return SRSessionRollbackFinish;
        case SRSessionForegroundPending:
        case SRSessionRestorePending:
            return SRSessionPolicyExpired(p, now) ? SRSessionRollbackUnresolved : SRSessionRollbackWait;
        case SRSessionForegroundOwned:
            if (!identity) return SRSessionRollbackUnresolved;
            /* Another actor already restored NO: do not write even with a lease. */
            if (!foreground) return SRSessionRollbackFinish;
            if (SRSessionPolicyExpired(p, now) || !proof) return SRSessionRollbackUnresolved;
            return SRSessionRollbackRestore;
        case SRSessionForegroundUnresolved: return SRSessionRollbackUnresolved;
    }
    return SRSessionRollbackUnresolved;
}
bool SRSessionPolicyObserveForegroundAbsent(SRSessionPolicy *p, bool identity) {
    if (!p || p->phase != SRSessionClosing ||
        p->foreground != SRSessionForegroundOwned || !identity) return false;
    p->foreground = SRSessionForegroundRestored;
    return true;
}
bool SRSessionPolicyBeginRestore(SRSessionPolicy *p) {
    if (!p || p->phase != SRSessionClosing || p->foreground != SRSessionForegroundOwned)
        return false;
    p->foreground = SRSessionRestorePending;
    p->pending_generation = p->generation;
    return true;
}
void SRSessionPolicyUnresolved(SRSessionPolicy *p) {
    if (p && p->phase != SRSessionClosed) {
        p->foreground = SRSessionForegroundUnresolved;
        p->pending_generation = 0;
    }
}
bool SRSessionPolicyFinishClose(SRSessionPolicy *p, bool unresolved) {
    if (!p || p->phase != SRSessionClosing) return false;
    if (!unresolved && p->foreground != SRSessionForegroundUntouched &&
        p->foreground != SRSessionForegroundRestored) return false;
    if (unresolved) p->foreground = SRSessionForegroundUnresolved;
    p->pending_generation = 0;
    p->phase = SRSessionClosed;
    if (p->generation != UINT64_MAX) ++p->generation;
    return true;
}
bool SRSessionPolicyTakeStartCompletion(SRSessionPolicy *p) {
    if (!p || p->start_delivered || (p->phase != SRSessionAttached &&
        p->phase != SRSessionClosing && p->phase != SRSessionClosed)) return false;
    p->start_delivered = true;
    return true;
}
bool SRSessionPolicyTakeCloseCompletion(SRSessionPolicy *p) {
    if (!p || p->close_delivered || p->phase != SRSessionClosed) return false;
    p->close_delivered = true;
    return true;
}
