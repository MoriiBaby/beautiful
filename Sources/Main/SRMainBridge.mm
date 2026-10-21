#import "SRMainBridge.h"
#import "SceneBridge/SRSceneHost.h"
#import "../Shared/SRRuntime.h"

BOOL SRMainSceneHostingAvailable(void) {
    return [SRSceneHost isAvailable] && SRRuntimeCanActivate();
}
NSString *SRMainSceneHostingBlocker(void) {
    if (![SRSceneHost isAvailable]) return [SRSceneHost unavailableReason];
    return @"Reconstruction disabled or original Stheno module is present.";
}
id SRMainCreateSceneSession(void) { return [SRSceneHost new]; }
static BOOL SRInvalidSession(NSError **error) {
    if (error) *error = [NSError errorWithDomain:@"com.local.stheno.session" code:1
        userInfo:@{NSLocalizedDescriptionKey: @"Invalid reconstructed scene session"}];
    return NO;
}
BOOL SRMainAttachScene(id session, NSString *bundleID, UIView *target, NSError **error) {
    if (![session isKindOfClass:SRSceneHost.class]) return SRInvalidSession(error);
    return [(SRSceneHost *)session attachBundleIdentifier:bundleID toView:target error:error];
}
BOOL SRMainResizeScene(id session, CGRect bounds, NSError **error) {
    if (![session isKindOfClass:SRSceneHost.class]) return SRInvalidSession(error);
    return [(SRSceneHost *)session resizeToBounds:bounds error:error];
}
BOOL SRMainCloseScene(id session, NSError **error) {
    if (![session isKindOfClass:SRSceneHost.class]) return SRInvalidSession(error);
    return [(SRSceneHost *)session closeWithError:error];
}
