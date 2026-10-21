#ifndef SR_SESSION_POLICY_H
#define SR_SESSION_POLICY_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    SRSessionIdle, SRSessionAcquiring, SRSessionActivating,
    SRSessionWaitingLayers, SRSessionAttached, SRSessionClosing, SRSessionClosed
} SRSessionPhase;
typedef enum {
    SRSessionForegroundUntouched, SRSessionForegroundPending,
    SRSessionForegroundOwned, SRSessionRestorePending,
    SRSessionForegroundRestored, SRSessionForegroundUnresolved
} SRSessionForeground;
typedef enum {
    SRSessionSelectionWait, SRSessionSelectionUnique,
    SRSessionSelectionAmbiguous, SRSessionSelectionStale
} SRSessionSelection;
typedef enum {
    SRSessionRollbackWait, SRSessionRollbackFinish,
    SRSessionRollbackRestore, SRSessionRollbackUnresolved
} SRSessionRollback;

typedef struct {
    uint64_t generation;
    uint64_t pending_generation;
    double deadline;
    SRSessionPhase phase;
    SRSessionForeground foreground;
    bool start_delivered;
    bool close_delivered;
} SRSessionPolicy;

void SRSessionPolicyInit(SRSessionPolicy *policy);
bool SRSessionPolicyBegin(SRSessionPolicy *policy, double now, double timeout);
bool SRSessionPolicyAccept(const SRSessionPolicy *policy, uint64_t generation);
bool SRSessionPolicyExpired(const SRSessionPolicy *policy, double now);
SRSessionSelection SRSessionPolicySelect(size_t matches, bool same_identity);
/* An unknown or target-frontmost identity NEVER authorizes a settings write. */
bool SRSessionPolicyMayMutate(bool same_identity, bool frontmost_identity_known,
                             bool target_is_frontmost, bool restoring,
                             bool owns_foreground_change);
/* Already-foreground scenes are borrowed without changing or owning that field. */
bool SRSessionPolicyAcquired(SRSessionPolicy *policy, uint64_t generation,
                             bool already_foreground, bool mutation_proved);
bool SRSessionPolicyExpectsCallback(const SRSessionPolicy *policy,
                                    uint64_t generation, bool restoring);
/* Cancellation permits acknowledgement of an old pending write, NEVER attach. */
bool SRSessionPolicyCompleteForeground(SRSessionPolicy *policy, uint64_t generation,
                                       bool restoring, bool confirmed);
bool SRSessionPolicyAttach(SRSessionPolicy *policy, uint64_t generation);
bool SRSessionPolicyBeginClose(SRSessionPolicy *policy, double now, double timeout);
SRSessionRollback SRSessionPolicyRollback(const SRSessionPolicy *policy, double now,
                                          bool same_identity, bool foreground_now,
                                          bool ownership_proved);
bool SRSessionPolicyObserveForegroundAbsent(SRSessionPolicy *policy, bool same_identity);
bool SRSessionPolicyBeginRestore(SRSessionPolicy *policy);
void SRSessionPolicyUnresolved(SRSessionPolicy *policy);
bool SRSessionPolicyFinishClose(SRSessionPolicy *policy, bool unresolved);
bool SRSessionPolicyTakeStartCompletion(SRSessionPolicy *policy);
bool SRSessionPolicyTakeCloseCompletion(SRSessionPolicy *policy);

#ifdef __cplusplus
}
#endif
#endif
