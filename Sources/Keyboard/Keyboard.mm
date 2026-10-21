#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <notify.h>
#import <dispatch/dispatch.h>
#import "../Shared/SRRuntime.h"
#import "../Shared/SRPolicy.h"

static NSString *gBundleID;
static NSString *gFrontmost = @"";
static UIScene *gFirstScene;
static BOOL gMode169 = NO;
static BOOL gHookScreen = YES; // Both original slices: __data VA 0xc160 = 1.
static BOOL gHooksActive = NO;
static int gNotificationToken;
static BOOL gNotificationRegistered;
static IMP gActiveOriginal, gWindowOriginal, gSceneOriginal, gBoundsOriginal;

static NSDictionary *SRKeyboardPreferences(void) {
    NSString *path = SRRootPath(@"/var/mobile/Library/Preferences/com.nx.stheno.plist");
    return path ? [NSDictionary dictionaryWithContentsOfFile:path] : nil;
}
static BOOL SRKeyboardBundleAllowed(NSString *bundleID) {
    id apps = SRKeyboardPreferences()[@"Apps"];
    // Original consumes a SPACE-delimited string, not a plist array.
    if (![apps isKindOfClass:NSString.class] || !bundleID.length) return NO;
    return [[apps componentsSeparatedByString:@" "] containsObject:bundleID];
}
static void SRKeyboardReload169(void) {
    NSDictionary *prefs = SRKeyboardPreferences();
    id value = prefs[@"169"];
    if (!prefs || !value || ![value respondsToSelector:@selector(boolValue)]) return;
    gMode169 = SRStickyFlagNext(gMode169, true, true, [value boolValue]);
}
static void SRKeyboardReadFrontmost(void) {
    NSString *path = SRRootPath(@"/tmp/stheno_frontmost.json");
    if (!path) return;
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&error];
    if (!data || error) return;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error || ![object isKindOfClass:NSDictionary.class]) return;
    id bundleID = object[@"id"];
    // Missing/invalid JSON keeps old state; extra type guard prevents bad IPC crashing UIKit.
    if ([bundleID isKindOfClass:NSString.class]) gFrontmost = [bundleID copy];
}
static id SRKeyboardActive(id receiver, SEL selector) {
    if (gHooksActive) SRKeyboardReadFrontmost(); // Before original, not after returned instance.
    return ((id (*)(id, SEL))gActiveOriginal)(receiver, selector);
}
static id SRKeyboardWindow(id receiver, SEL selector, UIScreen *screen, BOOL create) {
    id window = ((id (*)(id, SEL, UIScreen *, BOOL))gWindowOriginal)(receiver, selector, screen, create);
    if (!gHooksActive || !SRKeyboardShouldResize(window != nil,
            [gFrontmost isEqualToString:gBundleID])) return window;
    // Runtime signature checks below are not a claim of all-system semantic compatibility.
    if (![window isKindOfClass:UIWindow.class]) return window;
    gHookScreen = NO;
    @try {
        CGRect screenBounds = UIScreen.mainScreen.bounds;
        SRRect input = {screenBounds.origin.x, screenBounds.origin.y,
                        screenBounds.size.width, screenBounds.size.height};
        SRKeyboardGeometry geometry = SRKeyboardGeometryForScreen(input);
        SRRect f = geometry.frame, b = geometry.bounds;
        [(UIWindow *)window setFrame:CGRectMake(f.x, f.y, f.width, f.height)];
        [(UIWindow *)window setBounds:CGRectMake(b.x, b.y, b.width, b.height)];
    } @finally {
        gHookScreen = YES;
    }
    return window;
}
// init methods consume self and return +1. Preserve that ABI under ARC on BOTH calls.
typedef id (*SRSceneInitFunction)(id __attribute__((ns_consumed)), SEL, id, id)
    __attribute__((ns_returns_retained));
static id SRKeyboardScene(id __attribute__((ns_consumed)) receiver, SEL selector,
                          id session, id options) __attribute__((ns_returns_retained));
static id SRKeyboardScene(id __attribute__((ns_consumed)) receiver, SEL selector, id session, id options) {
    id scene = ((SRSceneInitFunction)gSceneOriginal)(receiver, selector, session, options);
    if (gHooksActive && !gFirstScene && [scene isKindOfClass:UIScene.class]) {
        SRKeyboardReload169();
        gFirstScene = scene;
    }
    return scene;
}
static CGRect SRKeyboardBounds(id receiver, SEL selector, NSInteger orientation) {
    const char *args[] = {@encode(NSInteger)};
    if (gHooksActive && SRKeyboardShouldForwardBounds(gMode169, gHookScreen) && gFirstScene &&
        SRCheckHookSignature(object_getClass(gFirstScene), selector, @encode(CGRect), args, 1)) {
        return ((CGRect (*)(id, SEL, NSInteger))objc_msgSend)(gFirstScene, selector, orientation);
    }
    return ((CGRect (*)(id, SEL, NSInteger))gBoundsOriginal)(receiver, selector, orientation);
}
static void SRKeyboardDismissResponder(void) {
    if (!gHooksActive) return;
    Class impl = objc_getClass("UIKeyboardImpl");
    SEL active = sel_registerName("activeInstance");
    if (!SRCheckHookSignature(object_getClass(impl), active, @encode(id), NULL, 0)) return;
    id keyboard = ((id (*)(id, SEL))objc_msgSend)(impl, active);
    SEL delegate = sel_registerName("delegateAsResponder");
    if (!keyboard || !SRCheckHookSignature(object_getClass(keyboard), delegate, @encode(id), NULL, 0)) return;
    id responder = ((id (*)(id, SEL))objc_msgSend)(keyboard, delegate);
    if ([responder isKindOfClass:UIResponder.class] && [responder canResignFirstResponder])
        [responder resignFirstResponder];
}
__attribute__((constructor)) static void SRKeyboardInitialize(void) {
    @autoreleasepool {
        if (!SRRuntimeCanActivate()) return;
        gBundleID = [NSBundle.mainBundle.bundleIdentifier copy];
        if (!SRKeyboardBundleAllowed(gBundleID)) return;
        Class automatic = object_getClass(objc_getClass("UIKeyboardAutomatic"));
        Class remote = object_getClass(objc_getClass("UIRemoteKeyboardWindow"));
        Class scene = objc_getClass("UIScene"), screen = objc_getClass("UIScreen");
        SEL active = sel_registerName("activeInstance");
        SEL remoteSelector = sel_registerName("remoteKeyboardWindowForScreen:create:");
        SEL sceneSelector = sel_registerName("initWithSession:connectionOptions:");
        SEL boundsSelector = sel_registerName("_boundsForInterfaceOrientation:");
        const char *remoteArgs[] = {@encode(id), @encode(BOOL)};
        const char *sceneArgs[] = {@encode(id), @encode(id)};
        const char *boundsArgs[] = {@encode(NSInteger)};
        if (!SRCheckHookSignature(automatic, active, @encode(id), NULL, 0) ||
            !SRCheckHookSignature(remote, remoteSelector, @encode(id), remoteArgs, 2) ||
            !SRCheckHookSignature(scene, sceneSelector, @encode(id), sceneArgs, 2) ||
            !SRCheckHookSignature(screen, boundsSelector, @encode(CGRect), boundsArgs, 1)) {
            NSLog(@"[SthenoRebuildKeyboard] ABI preflight failed; no hooks installed");
            return;
        }
        // Preflight is not a transaction. Until ALL originals are captured, wrappers pass through.
        gHooksActive = SRInstallHook(automatic, active, (IMP)SRKeyboardActive, &gActiveOriginal,
            @encode(id), NULL, 0) &&
            SRInstallHook(remote, remoteSelector, (IMP)SRKeyboardWindow, &gWindowOriginal,
                @encode(id), remoteArgs, 2) &&
            SRInstallHook(scene, sceneSelector, (IMP)SRKeyboardScene, &gSceneOriginal,
                @encode(id), sceneArgs, 2) &&
            SRInstallHook(screen, boundsSelector, (IMP)SRKeyboardBounds, &gBoundsOriginal,
                @encode(CGRect), boundsArgs, 1);
        if (!gHooksActive) return;
        gNotificationRegistered = notify_register_dispatch("com.nx.SthenoKeyboard", &gNotificationToken,
            dispatch_get_main_queue(), ^(int token) { (void)token; SRKeyboardDismissResponder(); }) == NOTIFY_STATUS_OK;
        if (!gNotificationRegistered) {
            // Installed wrappers stay pass-through if the IPC half of the contract is unavailable.
            gHooksActive = NO;
            NSLog(@"[SthenoRebuildKeyboard] Notification registration failed; behavior disabled");
        }
    }
}
__attribute__((destructor)) static void SRKeyboardShutdown(void) {
    if (gNotificationRegistered) notify_cancel(gNotificationToken);
}
