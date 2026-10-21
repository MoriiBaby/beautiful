#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Deliberately fail-closed; this is not a scene-hosting implementation.
#define SR_SCENE_HOSTING_IMPLEMENTED 0
FOUNDATION_EXPORT NSErrorDomain const SRSceneHostErrorDomain;
typedef NS_ERROR_ENUM(SRSceneHostErrorDomain, SRSceneHostError) {
    SRSceneHostErrorUnavailable = 1,
    SRSceneHostErrorInvalidArgument = 2,
    SRSceneHostErrorMainThreadRequired = 3,
};

/// Main-thread interface reserved for the real scene bridge. See SCENE-HOSTING.md.
/// This adapter never launches an app, retains a target view, or acquires a scene.
@interface SRSceneHost : NSObject
@property (class, nonatomic, readonly, getter=isAvailable) BOOL available;
@property (class, nonatomic, readonly, copy) NSString *unavailableReason;
@property (nonatomic, readonly, getter=isAttached) BOOL attached;
@property (nonatomic, readonly, nullable) UIView *hostedView;

/// Always fails after public-input checks. Swift imports BOOL/NSError as throws.
- (BOOL)attachBundleIdentifier:(NSString *)bundleIdentifier
                       toView:(UIView *)targetView
                        error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(attach(bundleIdentifier:to:));
/// Bounds in host coordinates, finite and strictly positive in both dimensions.
/// Always fails; changing an empty container is not a successful scene resize.
- (BOOL)resizeToBounds:(CGRect)bounds
                error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(resize(to:));
/// Idempotent local cleanup, main thread only. No remote resource was acquired;
/// success here does not assert that any application scene was closed.
- (BOOL)closeWithError:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(close());
@end

NS_ASSUME_NONNULL_END
