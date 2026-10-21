#import "SRMainBridge.h"
#import "SRWindowPolicy.h"
#import "SceneBridge/SRSceneSession.h"
#import "../Shared/SRRuntime.h"
#include <math.h>

BOOL SRMainSceneHostingAvailable(void) { return SRSceneSession.available; }
NSString *SRMainSceneHostingBlocker(void) {
    NSError *error = nil;
    [SRSceneSession checkAvailabilityWithError:&error];
    return error.localizedDescription ?: @"Scene session is disabled pending interactivity and restore validation.";
}
id SRMainCreateSceneSession(void) { return [SRSceneSession new]; }
static void SRInvalidSession(SRMainCompletion completion) {
    NSError *error = [NSError errorWithDomain:@"com.local.stheno.session" code:1
        userInfo:@{NSLocalizedDescriptionKey: @"Invalid reconstructed scene session"}];
    dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
}
static CGAffineTransform SRDisplayTransform(CGRect target, CGRect content) {
    CGFloat scale = fmin(target.size.width / content.size.width,
                         target.size.height / content.size.height);
    return CGAffineTransformMakeScale(scale, scale);
}
void SRMainAttachSceneAsync(id session, NSString *bundleID, UIView *target, SRMainCompletion completion) {
    if (![session isKindOfClass:SRSceneSession.class]) { SRInvalidSession(completion); return; }
    // Public main-screen dimensions are a display baseline, not a remote resize protocol.
    // Host layers retain their native bounds; letterbox them rather than stretching app output.
    CGRect native = UIScreen.mainScreen.bounds;
    native.origin = CGPointZero;
    [(SRSceneSession *)session startBundleIdentifier:bundleID sceneIdentifier:nil inView:target
        contentBounds:native displayTransform:SRDisplayTransform(target.bounds, native)
        launchIfMissing:NO timeout:8.0 completion:completion];
    // No foreground authority is fabricated. Background acquisition refuses explicitly.
}
void SRMainResizeSceneAsync(id session, CGRect bounds, SRMainCompletion completion) {
    if (![session isKindOfClass:SRSceneSession.class]) { SRInvalidSession(completion); return; }
    CGRect native = UIScreen.mainScreen.bounds; native.origin = CGPointZero;
    [(SRSceneSession *)session setContentBounds:native displayTransform:SRDisplayTransform(bounds, native)
        completion:completion];
}
void SRMainCloseSceneAsync(id session, SRMainCompletion completion) {
    if (![session isKindOfClass:SRSceneSession.class]) { SRInvalidSession(completion); return; }
    [(SRSceneSession *)session closeWithCompletion:completion];
}
void SRMainSetInvalidationHandler(id session, SRMainCompletion handler) {
    if ([session isKindOfClass:SRSceneSession.class])
        [(SRSceneSession *)session setInvalidationHandler:handler];
}
BOOL SRMainConstrainWindow(CGRect requested, CGRect screen, CGRect *result) {
    if (!result) return NO;
    SRWindowRect r = {requested.origin.x, requested.origin.y, requested.size.width, requested.size.height};
    SRWindowRect s = {screen.origin.x, screen.origin.y, screen.size.width, screen.size.height}, out;
    if (!SRWindowConstrain(r, s, &out)) return NO;
    *result = CGRectMake(out.x, out.y, out.width, out.height);
    return YES;
}
