#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "SRSessionPolicy.h"

#ifndef SR_ENABLE_SCENE_SESSION_LAB
#define SR_ENABLE_SCENE_SESSION_LAB 0
#endif

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSErrorDomain const SRSceneSessionErrorDomain;
typedef NS_ERROR_ENUM(SRSceneSessionErrorDomain, SRSceneSessionError) {
    SRSceneSessionErrorUnavailable = 1, SRSceneSessionErrorInvalidInput,
    SRSceneSessionErrorInvalidState, SRSceneSessionErrorRuntimeABI,
    SRSceneSessionErrorAmbiguous, SRSceneSessionErrorIdentityChanged,
    SRSceneSessionErrorLaunch, SRSceneSessionErrorTimeout,
    SRSceneSessionErrorCancelled, SRSceneSessionErrorForegroundAuthority,
    SRSceneSessionErrorLayers, SRSceneSessionErrorRollbackUnresolved,
    SRSceneSessionErrorException,
};
typedef void (^SRSceneSessionCompletion)(NSError * _Nullable error);

/// UNRESOLVED TYPED EXTENSION, not an implemented source of system authority.
/// An independently verified adapter must provide a session-exclusive field
/// lease. All methods/properties run on main. A YES begin must serialize system
/// foreground/settings/frontmost changes through end, establish a KNOWN exact
/// frontmost scene identifier (nil means positively known no frontmost scene),
/// and compare the foreground field's revision, not merely its boolean value.
/// Restoring may succeed ONLY while the most recent foreground change is ours.
/// The lease must merge/serialize other settings updates across the async call;
/// a bundle-only frontmost check or a UI-thread assertion is NOT sufficient.
/// No such provider/private selector is supplied or inferred from metadata.
@protocol SRSceneSessionForegroundLease <NSObject>
@property (nonatomic, readonly) id scene;
@property (nonatomic, readonly, copy) NSString *sceneIdentifier;
@property (nonatomic, readonly) BOOL frontmostIdentityKnown;
@property (nonatomic, readonly, copy, nullable) NSString *frontmostSceneIdentifier;
@property (nonatomic, readonly) BOOL ownsForegroundChange;
- (BOOL)beginMutationRestoring:(BOOL)restoring error:(NSError * _Nullable * _Nullable)error;
/// Must also verify the held identity/frontmost/revision guard at acknowledgement.
- (BOOL)endMutationRestoring:(BOOL)restoring observedForeground:(BOOL)foreground
                     error:(NSError * _Nullable * _Nullable)error;
/// Local release only, NEVER a remote settings write. An unfinished write is
/// recorded as unresolved; this must NOT claim an uncertain mutation was undone.
- (void)invalidateWithoutMutation;
@end
@protocol SRSceneSessionForegroundAuthority <NSObject>
- (nullable id<SRSceneSessionForegroundLease>)leaseForScene:(id)scene
    identifier:(NSString *)identifier bundleIdentifier:(NSString *)bundleIdentifier
    error:(NSError * _Nullable * _Nullable)error;
@end

/// Executable, disabled candidate; NOT the packaging/interactive-hosting gate.
/// Single admitted start; retain and explicitly close this self-held session.
/// All requests enqueue on main, even when called on main; every completion is
/// delivered asynchronously on main exactly once. Properties are MAIN ONLY.
/// No hooks, scene creation/destroy, process kill, screenshots or fake success.
@interface SRSceneSession : NSObject
@property (class, nonatomic, readonly, getter=isAvailable) BOOL available;
+ (BOOL)checkAvailabilityWithError:(NSError * _Nullable * _Nullable)error;
@property (nonatomic, readonly) SRSessionPhase phase;
@property (nonatomic, readonly, getter=isAttached) BOOL attached;
@property (nonatomic, readonly, nullable) UIView *hostedView;
@property (nonatomic, readonly, copy, nullable) NSString *sceneIdentifier;
/// Includes unexpected refresh/identity failures after start already succeeded.
@property (nonatomic, readonly, nullable) NSError *terminalError;
/// Asynchronous one-shot notification when the admitted session begins an error close.
@property (nonatomic, copy, nullable) SRSceneSessionCompletion invalidationHandler;

- (instancetype)initWithForegroundAuthority:(nullable id<SRSceneSessionForegroundAuthority>)authority;
- (instancetype)init;
/// identifier=nil requires exactly ONE matching scene. A specified identifier
/// must match BOTH bundle and scene; ambiguity is never resolved by first match.
/// timeout is 0.05...30s for acquisition+activation+layers. A single suspended
/// launch is optional; it does not confer ownership and is never undone by kill.
/// contentBounds/transform describe local display only, NOT remote scene resize
/// or a claim that transformed touch/focus delivery has been verified.
- (void)startBundleIdentifier:(NSString *)bundleIdentifier
             sceneIdentifier:(nullable NSString *)identifier
                      inView:(UIView *)targetView
               contentBounds:(CGRect)contentBounds
            displayTransform:(CGAffineTransform)transform
             launchIfMissing:(BOOL)launchIfMissing
                     timeout:(NSTimeInterval)timeout
                  completion:(SRSceneSessionCompletion)completion;
- (void)refreshLayersWithCompletion:(SRSceneSessionCompletion)completion;
- (void)setContentBounds:(CGRect)bounds displayTransform:(CGAffineTransform)transform
             completion:(SRSceneSessionCompletion)completion;
/// Both invalidate the start generation and detach owned UIKit views at once.
/// Pending activation/rollback acknowledgements have a separate 2s close bound.
/// nil close error means untouched/observably restored state, not app termination.
/// Timeout/missing ownership proof yields RollbackUnresolved, never a blind NO.
- (void)cancelWithCompletion:(SRSceneSessionCompletion)completion;
- (void)closeWithCompletion:(SRSceneSessionCompletion)completion;
@end
NS_ASSUME_NONNULL_END
