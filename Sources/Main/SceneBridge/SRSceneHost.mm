#import "SRSceneHost.h"
#include <cmath>

#if !__has_feature(objc_arc)
#error SRSceneHost requires ARC
#endif

NSErrorDomain const SRSceneHostErrorDomain = @"com.local.stheno.scene-host";

static BOOL SRFail(NSError **error, SRSceneHostError code, NSString *reason) {
    if (error) {
        *error = [NSError errorWithDomain:SRSceneHostErrorDomain code:code
                                userInfo:@{NSLocalizedDescriptionKey: reason}];
    }
    return NO;
}

static BOOL SRRequireMainThread(NSError **error) {
    return [NSThread isMainThread] || SRFail(error, SRSceneHostErrorMainThreadRequired,
                                           @"Scene operations require the main thread.");
}

@implementation SRSceneHost
+ (BOOL)isAvailable { return NO; }
+ (NSString *)unavailableReason {
    return @"Real app-scene hosting is disabled: input routing, scene ownership, "
            "and safe teardown contracts are not established. See SCENE-HOSTING.md.";
}
- (BOOL)isAttached { return NO; }
- (UIView *)hostedView { return nil; }

- (BOOL)attachBundleIdentifier:(NSString *)bundleIdentifier
                       toView:(UIView *)targetView
                        error:(NSError **)error {
    if (error) *error = nil;
    if (!SRRequireMainThread(error)) return NO;
    if (![bundleIdentifier isKindOfClass:NSString.class] || bundleIdentifier.length == 0 ||
        ![targetView isKindOfClass:UIView.class]) {
        return SRFail(error, SRSceneHostErrorInvalidArgument,
                      @"A nonempty bundle identifier and a target UIView are required.");
    }
    return SRFail(error, SRSceneHostErrorUnavailable, SRSceneHost.unavailableReason);
}

- (BOOL)resizeToBounds:(CGRect)bounds error:(NSError **)error {
    if (error) *error = nil;
    if (!SRRequireMainThread(error)) return NO;
    if (!std::isfinite(bounds.origin.x) || !std::isfinite(bounds.origin.y) ||
        !std::isfinite(bounds.size.width) || !std::isfinite(bounds.size.height) ||
        bounds.size.width <= 0 || bounds.size.height <= 0) {
        return SRFail(error, SRSceneHostErrorInvalidArgument,
                      @"Host bounds must be finite with positive width and height.");
    }
    return SRFail(error, SRSceneHostErrorUnavailable, SRSceneHost.unavailableReason);
}

- (BOOL)closeWithError:(NSError **)error {
    if (error) *error = nil;
    if (!SRRequireMainThread(error)) return NO;
    // Only the never-attached adapter is being closed, not an FBScene or process.
    return YES;
}
@end
