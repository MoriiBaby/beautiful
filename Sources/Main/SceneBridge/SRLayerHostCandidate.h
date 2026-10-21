#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Explicit build-time lab opt-in only. Never use this flag as a packaging gate.
#ifndef SR_ENABLE_LAYER_HOST_LAB
#define SR_ENABLE_LAYER_HOST_LAB 0
#endif

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSErrorDomain const SRLayerHostCandidateErrorDomain;
typedef NS_ERROR_ENUM(SRLayerHostCandidateErrorDomain, SRLayerHostCandidateError) {
    SRLayerHostCandidateErrorDisabled = 1,
    SRLayerHostCandidateErrorMainThread = 2,
    SRLayerHostCandidateErrorInvalidInput = 3,
    SRLayerHostCandidateErrorRuntimeABI = 4,
    SRLayerHostCandidateErrorConstruction = 5,
};

/// DISABLED LAB ONLY. Owns newly constructed views/layer references, never the
/// remote scene lifecycle. No launch, foreground, kill, hooks or input promise.
/// Caller supplies an already borrowed FBScene and its current ordered layers.
/// All access and explicit cleanup must occur on the main thread.
@interface SRLayerHostCandidate : NSObject
@property (class, nonatomic, readonly, getter=isLabEnabled) BOOL labEnabled;
@property (nonatomic, copy, readonly) NSArray<UIView *> *hostViews;
@property (nonatomic, copy, readonly) NSArray<UIView *> *keyboardViews;
@property (nonatomic, readonly, getter=isPrepared) BOOL prepared;

/// Atomic replacement: any failed check/init leaves existing owned views intact.
/// Does not insert views into a window/container. Inspect arrays only after YES.
- (BOOL)rebuildForBorrowedScene:(id)scene
                 clientLayers:(NSOrderedSet *)layers
                        error:(NSError * _Nullable * _Nullable)error;
/// Applies only the public UIKit transform to actual host views; not a remote
/// scene resize, and not a verified touch-coordinate/focus transformation.
- (BOOL)applyDisplayTransform:(CGAffineTransform)transform
                        error:(NSError * _Nullable * _Nullable)error;
/// Removes/releases only this instance's newly constructed views and references.
/// Does not deactivate, invalidate, destroy or terminate the borrowed scene.
- (BOOL)closeWithError:(NSError * _Nullable * _Nullable)error;
@end
NS_ASSUME_NONNULL_END
