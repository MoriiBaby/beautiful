#import "SRSceneSession.h"
#import "SRLayerHostCandidate.h"
#import "../../Shared/SRRuntime.h"
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <QuartzCore/QuartzCore.h>
#include <atomic>
#include <cmath>
#include <cstring>
#include <memory>

#if !__has_feature(objc_arc)
#error SRSceneSession requires ARC
#endif

NSErrorDomain const SRSceneSessionErrorDomain = @"com.local.stheno.scene-session-lab";
typedef id (*SRSessionObject0)(id, SEL);
typedef id (*SRSessionObject1)(id, SEL, id);
typedef BOOL (*SRSessionBool0)(id, SEL);
typedef void (*SRSessionSetBool)(id, SEL, BOOL);
typedef void (^SRSessionEnumeratedScene)(id);
typedef void (*SRSessionEnumerate)(id, SEL, SRSessionEnumeratedScene);
typedef BOOL (*SRSessionLaunch)(id, SEL, id, BOOL);
typedef void (^SRSessionTransitionDone)(void);
typedef void (*SRSessionUpdate)(id, SEL, id, id, SRSessionTransitionDone);

static NSError *SRError(SRSceneSessionError code, NSString *message) {
    return [NSError errorWithDomain:SRSceneSessionErrorDomain code:code
                          userInfo:@{NSLocalizedDescriptionKey: message}];
}
static BOOL SRFail(NSError **error, SRSceneSessionError code, NSString *message) {
    if (error) *error = SRError(code, message);
    return NO;
}
static void SRDeliver(SRSceneSessionCompletion completion, NSError *error) {
    if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
}
static BOOL SRGeometry(CGRect b, CGAffineTransform t) {
    double determinant = t.a * t.d - t.b * t.c;
    return std::isfinite(b.origin.x) && std::isfinite(b.origin.y) &&
        std::isfinite(b.size.width) && std::isfinite(b.size.height) &&
        b.size.width > 0 && b.size.height > 0 && std::isfinite(t.a) &&
        std::isfinite(t.b) && std::isfinite(t.c) && std::isfinite(t.d) &&
        std::isfinite(t.tx) && std::isfinite(t.ty) &&
        std::isfinite(determinant) && determinant != 0;
}

// These exact arm64 method encodings are ABI declarations, not a copy of any
// device report. Only 16.0.3 is allowlisted. Do NOT weaken @? to @ or B to c.
// Resolve once, compare that Method's full encoding, call its SAME typed IMP.
// No SRCheckHookSignature + redispatch, performSelector, objc_msgSend or hooks.
static IMP SRIMP(id receiver, SEL selector, const char *encoding, NSError **error) {
    Class cls = receiver ? object_getClass(receiver) : Nil;
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    const char *actual = method ? method_getTypeEncoding(method) : NULL;
    IMP imp = actual && strcmp(actual, encoding) == 0 ? method_getImplementation(method) : NULL;
    if (!imp) SRFail(error, SRSceneSessionErrorRuntimeABI,
                    [NSString stringWithFormat:@"Rejected exact ABI for %@.%@",
                     cls ? NSStringFromClass(cls) : @"nil", NSStringFromSelector(selector)]);
    return imp;
}
static id SRObject(id receiver, NSString *name, Class required, BOOL allowNil, NSError **error) {
    SEL sel = NSSelectorFromString(name);
    IMP imp = SRIMP(receiver, sel, "@16@0:8", error);
    if (!imp) return nil;
    id result = ((SRSessionObject0)imp)(receiver, sel);
    if ((!result && !allowNil) || (result && required && ![result isKindOfClass:required])) {
        SRFail(error, SRSceneSessionErrorRuntimeABI, [@"Unexpected result of " stringByAppendingString:name]);
        return nil;
    }
    return result;
}
static id SRLookup(id manager, NSString *identifier, NSError **error) {
    SEL sel = NSSelectorFromString(@"sceneWithIdentifier:");
    IMP imp = SRIMP(manager, sel, "@24@0:8@16", error);
    if (!imp) return nil;
    id result = ((SRSessionObject1)imp)(manager, sel, identifier);
    Class cls = NSClassFromString(@"FBScene");
    if (result && (!cls || ![result isKindOfClass:cls])) {
        SRFail(error, SRSceneSessionErrorRuntimeABI, @"Scene lookup returned a non-FBScene.");
        return nil;
    }
    return result;
}
static BOOL SRSceneIdentity(id scene, NSString **identifier, NSString **bundle, NSError **error) {
    Class sceneClass = NSClassFromString(@"FBScene");
    Class processClass = NSClassFromString(@"FBProcess");
    if (!sceneClass || !processClass || ![scene isKindOfClass:sceneClass])
        return SRFail(error, SRSceneSessionErrorRuntimeABI, @"Borrowed object is not a measured scene class.");
    NSString *sid = SRObject(scene, @"identifier", NSString.class, NO, error);
    if (!sid.length) return SRFail(error, SRSceneSessionErrorIdentityChanged, @"Scene has no stable string identifier.");
    id process = SRObject(scene, @"clientProcess", processClass, NO, error);
    if (!process) return NO;
    NSString *bid = SRObject(process, @"bundleIdentifier", NSString.class, NO, error);
    if (!bid.length) return SRFail(error, SRSceneSessionErrorIdentityChanged, @"Scene has no bundle identity.");
    *identifier = [sid copy]; *bundle = [bid copy];
    return YES;
}
static id SRFreshSettings(id scene, BOOL *foreground, NSError **error) {
    id settings = SRObject(scene, @"uiSettings", Nil, NO, error);
    if (!settings) return nil;
    // Standard NSCopying ownership is known to ARC. No private init is called.
    if (![settings respondsToSelector:@selector(mutableCopyWithZone:)]) {
        SRFail(error, SRSceneSessionErrorRuntimeABI, @"uiSettings is not mutable-copyable.");
        return nil;
    }
    id copy = [settings mutableCopy];
    Class cls = NSClassFromString(@"UIMutableApplicationSceneSettings");
    if (!cls || copy == settings || ![copy isKindOfClass:cls]) {
        SRFail(error, SRSceneSessionErrorRuntimeABI, @"Unexpected mutable uiSettings class.");
        return nil;
    }
    SEL sel = NSSelectorFromString(@"isForeground");
    IMP imp = SRIMP(copy, sel, "B16@0:8", error);
    if (!imp) return nil;
    *foreground = ((SRSessionBool0)imp)(copy, sel);
    return copy;
}
static BOOL SRLayerPointersEqual(NSOrderedSet *a, NSOrderedSet *b) {
    if (a.count != b.count) return NO;
    for (NSUInteger i = 0; i < a.count; ++i) if (a[i] != b[i]) return NO;
    return YES;
}
// The observed enumeration callback has ONE object, no invented stop pointer.
// Only inline main-thread callbacks are accepted. Escaped/foreign callbacks can
// retain this guard but cannot touch the collection or resurrect a session.
struct SREnumerationGuard {
    std::atomic<bool> open{true};
    std::atomic<bool> foreign{false};
};

@interface SRSceneSession ()
- (void)tick;
- (void)beginClose:(nullable NSError *)reason;
- (BOOL)validateIdentity:(NSError **)error;
- (BOOL)refresh:(BOOL)force error:(NSError **)error;
- (void)advanceClose;
- (void)finishCloseUnresolved:(BOOL)unresolved;
- (BOOL)sendSettings:(id)settings restoring:(BOOL)restoring error:(NSError **)error;
- (void)acknowledgedGeneration:(uint64_t)generation restoring:(BOOL)restoring;
- (BOOL)activateAcquiredScene:(NSError **)error;
- (BOOL)beginGuardRestoring:(BOOL)restoring error:(NSError **)error;
- (BOOL)findScene:(id __strong *)selected identifier:(NSString **)identifier error:(NSError **)error;
- (BOOL)launchSuspended:(NSError **)error;
- (void)deliverStart:(nullable NSError *)error;
- (void)startTimer;
- (void)requestClose:(nullable NSError *)reason completion:(SRSceneSessionCompletion)completion;
@end

@implementation SRSceneSession {
    SRSessionPolicy _policy;
    id<SRSceneSessionForegroundAuthority> _authority;
    id<SRSceneSessionForegroundLease> _lease;
    BOOL _guardOpen;
    id _manager;
    id _scene;
    NSString *_bundle;
    NSString *_requestedIdentifier;
    NSString *_identifier;
    __weak UIView *_target;
    UIView *_container;
    SRLayerHostCandidate *_layersHost;
    NSOrderedSet *_layers;
    CGRect _contentBounds;
    CGAffineTransform _transform;
    BOOL _launchIfMissing;
    BOOL _launched;
    dispatch_source_t _timer;
    SRSceneSession *_keepAlive;
    SRSceneSessionCompletion _startCompletion;
    NSMutableArray<SRSceneSessionCompletion> *_closeCompletions;
    NSError *_terminalError;
    NSError *_closeError;
}
+ (BOOL)isAvailable { return [self checkAvailabilityWithError:NULL]; }
+ (BOOL)checkAvailabilityWithError:(NSError **)error {
    if (error) *error = nil;
    if (SR_ENABLE_SCENE_SESSION_LAB != 1 || !SRLayerHostCandidate.labEnabled)
        return SRFail(error, SRSceneSessionErrorUnavailable, @"Both scene-session and layer-host labs must be explicitly enabled.");
#if !defined(__arm64__) && !defined(__aarch64__)
    return SRFail(error, SRSceneSessionErrorUnavailable, @"Only the captured arm64 ABI is known.");
#endif
    NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
    if (sizeof(void *) != 8 || os.majorVersion != 16 || os.minorVersion != 0 || os.patchVersion != 3)
        return SRFail(error, SRSceneSessionErrorUnavailable, @"Only iOS 16.0.3 is sampled; iOS 15.4.1 and all other versions are refused.");
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"] ||
        !SRRuntimeCanActivate())
        return SRFail(error, SRSceneSessionErrorUnavailable, @"SpringBoard, explicit runtime opt-in and original-plugin exclusion are required.");
    return YES;
}
- (instancetype)init { return [self initWithForegroundAuthority:nil]; }
- (instancetype)initWithForegroundAuthority:(id<SRSceneSessionForegroundAuthority>)authority {
    self = [super init];
    if (self) {
        SRSessionPolicyInit(&_policy);
        _authority = authority;
        _closeCompletions = [NSMutableArray array];
    }
    return self;
}
- (SRSessionPhase)phase { NSAssert(NSThread.isMainThread, @"main only"); return _policy.phase; }
- (BOOL)isAttached { NSAssert(NSThread.isMainThread, @"main only"); return _policy.phase == SRSessionAttached; }
- (UIView *)hostedView { NSAssert(NSThread.isMainThread, @"main only"); return self.attached ? _container : nil; }
- (NSString *)sceneIdentifier { NSAssert(NSThread.isMainThread, @"main only"); return _identifier; }
- (NSError *)terminalError { NSAssert(NSThread.isMainThread, @"main only"); return _terminalError; }
- (void)deliverStart:(NSError *)error {
    if (!SRSessionPolicyTakeStartCompletion(&_policy)) return;
    SRSceneSessionCompletion block = _startCompletion;
    _startCompletion = nil;
    uint64_t generation = _policy.generation;
    // A queued success must not outlive a cancellation queued ahead of its
    // delivery. Reserve delivery once now, but revalidate success on delivery.
    dispatch_async(dispatch_get_main_queue(), ^{
        NSError *delivered = error;
        if (!delivered && (self->_policy.generation != generation || self->_policy.phase != SRSessionAttached))
            delivered = self->_terminalError ?: SRError(SRSceneSessionErrorCancelled, @"Start was cancelled before completion delivery.");
        if (block) block(delivered);
    });
}
- (void)startTimer {
    if (_timer) return;
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(_timer, DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC, 5 * NSEC_PER_MSEC);
    __weak SRSceneSession *weakSelf = self;
    dispatch_source_set_event_handler(_timer, ^{ [weakSelf tick]; });
    dispatch_resume(_timer);
}
- (void)startBundleIdentifier:(NSString *)bundleIdentifier sceneIdentifier:(NSString *)identifier
                      inView:(UIView *)targetView contentBounds:(CGRect)contentBounds
            displayTransform:(CGAffineTransform)transform launchIfMissing:(BOOL)launchIfMissing
                     timeout:(NSTimeInterval)timeout completion:(SRSceneSessionCompletion)completion {
    // Copy identities at the API boundary; a caller's mutable string is not a lease.
    NSString *bundle = [bundleIdentifier isKindOfClass:NSString.class] ? [bundleIdentifier copy] : nil;
    NSString *requested = [identifier isKindOfClass:NSString.class] ? [identifier copy] : nil;
    BOOL badIdentifier = identifier != nil && !requested.length;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSError *error = nil;
        if (self->_policy.phase != SRSessionIdle) {
            SRDeliver(completion, SRError(SRSceneSessionErrorInvalidState, @"This session already started or closed.")); return;
        }
        if (!bundle.length || badIdentifier || ![targetView isKindOfClass:UIView.class] ||
            !SRGeometry(contentBounds, transform) || !std::isfinite(timeout) || timeout < 0.05 || timeout > 30) {
            SRDeliver(completion, SRError(SRSceneSessionErrorInvalidInput, @"Valid identities, UIView, finite display geometry and a 0.05...30s timeout are required.")); return;
        }
        if (![SRSceneSession checkAvailabilityWithError:&error]) { SRDeliver(completion, error); return; }
        if (!SRSessionPolicyBegin(&self->_policy, CACurrentMediaTime(), timeout)) {
            SRDeliver(completion, SRError(SRSceneSessionErrorInvalidState, @"Cannot begin this generation.")); return;
        }
        self->_startCompletion = [completion copy];
        self->_bundle = bundle; self->_requestedIdentifier = requested;
        self->_target = targetView; self->_contentBounds = contentBounds; self->_transform = transform;
        self->_launchIfMissing = launchIfMissing;
        self->_keepAlive = self;
        [self startTimer];
        [self tick];
    });
}
- (BOOL)validateIdentity:(NSError **)error {
    if (!_scene || !_manager || !_identifier.length)
        return SRFail(error, SRSceneSessionErrorIdentityChanged, @"No borrowed scene identity.");
    id current = SRLookup(_manager, _identifier, error);
    if (current != _scene)
        return SRFail(error, SRSceneSessionErrorIdentityChanged, @"Scene lookup no longer resolves to the borrowed pointer.");
    NSString *sid = nil, *bid = nil;
    if (!SRSceneIdentity(_scene, &sid, &bid, error)) return NO;
    if (![sid isEqualToString:_identifier] || ![bid isEqualToString:_bundle])
        return SRFail(error, SRSceneSessionErrorIdentityChanged, @"Borrowed scene identity changed.");
    return YES;
}
- (BOOL)findScene:(id __strong *)selected identifier:(NSString **)selectedIdentifier error:(NSError **)error {
    if (!_manager) {
        Class cls = NSClassFromString(@"FBSceneManager");
        if (!cls) return SRFail(error, SRSceneSessionErrorRuntimeABI, @"FBSceneManager is absent.");
        _manager = SRObject(cls, @"sharedInstance", cls, NO, error);
        if (!_manager) return NO;
    }
    SEL sel = NSSelectorFromString(@"enumerateScenesWithBlock:");
    IMP imp = SRIMP(_manager, sel, "v24@0:8@?16", error);
    if (!imp) return NO;
    NSMutableArray *matches = [NSMutableArray array];
    NSMutableArray<NSString *> *identifiers = [NSMutableArray array];
    __block NSError *failure = nil;
    auto guard = std::make_shared<SREnumerationGuard>();
    NSString *bundle = _bundle, *requested = _requestedIdentifier;
    @try {
    ((SRSessionEnumerate)imp)(_manager, sel, ^(id scene) {
        if (!NSThread.isMainThread) { guard->foreign.store(true); return; }
        if (!guard->open.load() || failure) return;
        @try {
            NSString *sid = nil, *bid = nil;
            if (!SRSceneIdentity(scene, &sid, &bid, &failure)) return;
            if (![bid isEqualToString:bundle] || (requested && ![sid isEqualToString:requested])) return;
            for (id existing in matches) if (existing == scene) return;
            [matches addObject:scene]; [identifiers addObject:sid];
        } @catch (NSException *exception) {
            (void)exception;
            failure = SRError(SRSceneSessionErrorException, @"Scene identity inspection raised an exception.");
        }
    });
    } @finally {
        guard->open.store(false);
    }
    if (guard->foreign.load()) failure = SRError(SRSceneSessionErrorRuntimeABI, @"Enumeration left the observed synchronous main-thread contract.");
    if (failure) { if (error) *error = failure; return NO; }
    BOOL same = YES;
    if (matches.count == 1) {
        id lookup = SRLookup(_manager, identifiers[0], error);
        if (error && *error) return NO;
        same = lookup == matches[0];
    }
    switch (SRSessionPolicySelect(matches.count, same)) {
        case SRSessionSelectionWait: *selected = nil; *selectedIdentifier = nil; return YES;
        case SRSessionSelectionUnique: *selected = matches[0]; *selectedIdentifier = identifiers[0]; return YES;
        case SRSessionSelectionAmbiguous:
            return SRFail(error, SRSceneSessionErrorAmbiguous, @"Multiple scenes match; provide a unique scene identifier.");
        case SRSessionSelectionStale:
            return SRFail(error, SRSceneSessionErrorIdentityChanged, @"Enumeration and identifier lookup disagree.");
    }
    return NO;
}
- (BOOL)launchSuspended:(NSError **)error {
    id application = SRObject(UIApplication.class, @"sharedApplication", UIApplication.class, NO, error);
    if (!application) return NO;
    SEL sel = NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
    IMP imp = SRIMP(application, sel, "B28@0:8@16B24", error);
    if (!imp) return NO;
    _launched = YES; // At most one attempt, even when a private call raises.
    if (!((SRSessionLaunch)imp)(application, sel, _bundle, YES))
        return SRFail(error, SRSceneSessionErrorLaunch, @"Suspended launch was refused.");
    return YES;
}
- (BOOL)beginGuardRestoring:(BOOL)restoring error:(NSError **)error {
    if (!_lease && !restoring && _authority)
        _lease = [_authority leaseForScene:_scene identifier:_identifier bundleIdentifier:_bundle error:error];
    if (!_lease || _lease.scene != _scene || ![_lease.sceneIdentifier isEqualToString:_identifier])
        return SRFail(error, SRSceneSessionErrorForegroundAuthority, @"No independently verified foreground field lease for this exact scene.");
    if (_guardOpen || ![_lease beginMutationRestoring:restoring error:error])
        return SRFail(error, SRSceneSessionErrorForegroundAuthority, @"Foreground mutation guard was refused.");
    _guardOpen = YES;
    // A known nil identity means home/no frontmost, not failure to find one.
    BOOL identity = [self validateIdentity:error];
    if (!SRSessionPolicyMayMutate(identity, _lease.frontmostIdentityKnown,
        [_lease.frontmostSceneIdentifier isEqualToString:_identifier], restoring,
        _lease.ownsForegroundChange))
        return SRFail(error, SRSceneSessionErrorForegroundAuthority, @"Frontmost identity or exclusive foreground revision ownership is not proved.");
    return YES;
}
- (BOOL)sendSettings:(id)settings restoring:(BOOL)restoring error:(NSError **)error {
    if (!_guardOpen || ![self validateIdentity:error]) return NO;
    if (SRSessionPolicyExpired(&_policy, CACurrentMediaTime()))
        return SRFail(error, SRSceneSessionErrorTimeout, @"Mutation deadline expired before dispatch.");
    SEL setter = NSSelectorFromString(@"setForeground:");
    SEL update = NSSelectorFromString(@"updateSettings:withTransitionContext:completion:");
    IMP setterIMP = SRIMP(settings, setter, "v20@0:8B16", error);
    if (!setterIMP) return NO;
    IMP updateIMP = SRIMP(_scene, update, "v40@0:8@16@24@?32", error);
    if (!updateIMP) return NO;
    // This is a fresh mutable COPY read inside the guard. Change ONLY one field;
    // never store/replay a stale settings snapshot on close.
    ((SRSessionSetBool)setterIMP)(settings, setter, !restoring);
    if (![self validateIdentity:error]) return NO;
    if (SRSessionPolicyExpired(&_policy, CACurrentMediaTime()))
        return SRFail(error, SRSceneSessionErrorTimeout, @"Mutation deadline expired during preparation.");
    BOOL admitted = restoring ? SRSessionPolicyBeginRestore(&_policy) :
        SRSessionPolicyAcquired(&_policy, _policy.generation, false, true);
    if (!admitted) return SRFail(error, SRSceneSessionErrorInvalidState, @"Write generation is no longer current.");
    uint64_t generation = _policy.pending_generation;
    __weak SRSceneSession *weakSelf = self;
    SRSessionTransitionDone done = ^{
        // Even a synchronous/foreign/duplicate callback is serialized on main.
        dispatch_async(dispatch_get_main_queue(), ^{
            SRSceneSession *session = weakSelf;
            if (session) [session acknowledgedGeneration:generation restoring:restoring];
        });
    };
    @try {
        ((SRSessionUpdate)updateIMP)(_scene, update, settings, nil, done);
    } @catch (NSException *exception) {
        (void)exception;
        // The method might have applied the write before throwing. Never call it
        // again or pretend there was no mutation merely because it threw.
        SRSessionPolicyUnresolved(&_policy);
        return SRFail(error, SRSceneSessionErrorRollbackUnresolved, @"Settings call raised after entry; remote outcome is unknown.");
    }
    return YES;
}
- (void)acknowledgedGeneration:(uint64_t)generation restoring:(BOOL)restoring {
    if (!SRSessionPolicyExpectsCallback(&_policy, generation, restoring)) return;
    if (SRSessionPolicyExpired(&_policy, CACurrentMediaTime())) {
        if (_policy.phase == SRSessionClosing) { [self finishCloseUnresolved:YES]; return; }
        [self beginClose:SRError(SRSceneSessionErrorTimeout, @"Activation acknowledgement exceeded the start deadline.")];
    }
    if (!SRSessionPolicyExpectsCallback(&_policy, generation, restoring)) return;
    @try {
        NSError *error = nil;
        BOOL foreground = NO;
        BOOL identity = [self validateIdentity:&error];
        id settings = identity ? SRFreshSettings(_scene, &foreground, &error) : nil;
        BOOL confirmed = settings && foreground == !restoring && _guardOpen;
        if (confirmed) confirmed = [_lease endMutationRestoring:restoring observedForeground:foreground error:&error];
        _guardOpen = NO;
        if (confirmed) confirmed = _lease.frontmostIdentityKnown &&
            ![_lease.frontmostSceneIdentifier isEqualToString:_identifier] &&
            (restoring || _lease.ownsForegroundChange);
        SRSessionPolicyCompleteForeground(&_policy, generation, restoring, confirmed);
        if (!confirmed) {
            [_lease invalidateWithoutMutation]; _lease = nil;
            if (_policy.phase != SRSessionClosing)
                [self beginClose:error ?: SRError(SRSceneSessionErrorRollbackUnresolved, @"Foreground callback did not establish an owned change.")];
        }
        [self tick];
    } @catch (NSException *exception) {
        (void)exception;
        SRSessionPolicyUnresolved(&_policy);
        [self beginClose:SRError(SRSceneSessionErrorRollbackUnresolved, @"Acknowledgement proof failed with an exception.")];
        [self advanceClose];
    }
}
- (BOOL)activateAcquiredScene:(NSError **)error {
    if (![self validateIdentity:error]) return NO;
    BOOL foreground = NO;
    id settings = SRFreshSettings(_scene, &foreground, error);
    if (!settings) return NO;
    if (foreground)
        return SRSessionPolicyAcquired(&_policy, _policy.generation, true, false);
    if (![self beginGuardRestoring:NO error:error]) return NO;
    // Discard the first read; acquire a fresh field value/settings copy UNDER
    // the independent guard. A concurrent change is not ours to overwrite.
    settings = SRFreshSettings(_scene, &foreground, error);
    if (!settings) return NO;
    if (foreground) return SRFail(error, SRSceneSessionErrorForegroundAuthority, @"Foreground changed before our guarded write.");
    return [self sendSettings:settings restoring:NO error:error];
}
- (BOOL)refresh:(BOOL)force error:(NSError **)error {
    if (_policy.phase != SRSessionWaitingLayers && _policy.phase != SRSessionAttached)
        return SRFail(error, SRSceneSessionErrorInvalidState, @"Layer refresh is not allowed in this phase.");
    if (![self validateIdentity:error]) return NO;
    UIView *target = _target;
    if (!target || !target.window || (_container && _container.superview != target))
        return SRFail(error, SRSceneSessionErrorLayers, @"The caller's live UIKit target is missing or our container was detached.");
    BOOL foreground = NO;
    if (!SRFreshSettings(_scene, &foreground, error)) return NO;
    if (!foreground) return SRFail(error, SRSceneSessionErrorIdentityChanged, @"System foreground changed; do not reactivate or keep stale hosts.");
    Class clientClass = NSClassFromString(@"FBSSceneClientSettings");
    if (!clientClass) return SRFail(error, SRSceneSessionErrorRuntimeABI, @"Measured client-settings class is absent.");
    id client = SRObject(_scene, @"clientSettings", clientClass, YES, error);
    if (error && *error) return NO;
    NSOrderedSet *layers = client ? SRObject(client, @"layers", NSOrderedSet.class, YES, error) : nil;
    if (error && *error) return NO;
    if (!layers.count) {
        if (_policy.phase == SRSessionWaitingLayers) return YES;
        return SRFail(error, SRSceneSessionErrorLayers, @"Previously hosted scene lost its ordered layers.");
    }
    if (!force && _layersHost && SRLayerPointersEqual(_layers, layers)) return YES;
    SRLayerHostCandidate *replacement = [SRLayerHostCandidate new];
    if (![replacement rebuildForBorrowedScene:_scene clientLayers:layers error:error]) return NO;
    // A keyboard alone is never a successful app display.
    if (!replacement.hostViews.count) {
        [replacement closeWithError:NULL];
        if (_policy.phase == SRSessionWaitingLayers) return YES;
        return SRFail(error, SRSceneSessionErrorLayers, @"No application context layer remains.");
    }
    UIView *container = _container ?: [[UIView alloc] initWithFrame:target.bounds];
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    container.clipsToBounds = NO;
    CGPoint center = CGPointMake(CGRectGetMidX(container.bounds), CGRectGetMidY(container.bounds));
    for (NSArray<UIView *> *views in @[replacement.hostViews, replacement.keyboardViews]) {
        for (UIView *view in views) { view.bounds = _contentBounds; view.center = center; }
    }
    if (![replacement applyDisplayTransform:_transform error:error]) return NO;
    // Revalidate AFTER building views as well as before reading layers. A
    // constructor/reentrant system event must not attach a replaced scene.
    if (![self validateIdentity:error]) return NO;
    if (SRSessionPolicyExpired(&_policy, CACurrentMediaTime()))
        return SRFail(error, SRSceneSessionErrorTimeout, @"Layer preparation exceeded the start deadline.");
    @try {
        for (UIView *view in replacement.hostViews) [container addSubview:view];
        for (UIView *view in replacement.keyboardViews) [container addSubview:view];
        if (!_container) [target addSubview:container];
    } @catch (NSException *exception) {
        (void)exception;
        [replacement closeWithError:NULL];
        if (!_container) [container removeFromSuperview];
        return SRFail(error, SRSceneSessionErrorLayers, @"UIKit attachment failed; previous owned views were kept.");
    }
    if (!container.window || ![self validateIdentity:error]) {
        [replacement closeWithError:NULL];
        if (!_container) [container removeFromSuperview];
        return SRFail(error, SRSceneSessionErrorLayers, @"No actual window contains the real host views.");
    }
    SRLayerHostCandidate *old = _layersHost;
    _layersHost = replacement; _layers = [layers copy]; _container = container;
    [old closeWithError:NULL];
    return YES;
}
- (void)tick {
    NSAssert(NSThread.isMainThread, @"main only");
    if (_policy.phase == SRSessionIdle || _policy.phase == SRSessionClosed) return;
    @try {
        if (_policy.phase == SRSessionClosing) { [self advanceClose]; return; }
        if (SRSessionPolicyExpired(&_policy, CACurrentMediaTime())) {
            [self beginClose:SRError(SRSceneSessionErrorTimeout, @"Scene acquisition, activation or layers exceeded the bounded start deadline.")];
            [self advanceClose]; return;
        }
        NSError *error = nil;
        if (_policy.phase == SRSessionAcquiring) {
            id scene = nil; NSString *identifier = nil;
            if (![self findScene:&scene identifier:&identifier error:&error]) { [self beginClose:error]; [self advanceClose]; return; }
            if (!scene) {
                if (_launchIfMissing && !_launched && ![self launchSuspended:&error]) {
                    [self beginClose:error]; [self advanceClose];
                }
                return;
            }
            _scene = scene; _identifier = [identifier copy];
            if (![self activateAcquiredScene:&error]) { [self beginClose:error]; [self advanceClose]; return; }
        }
        if (_policy.phase == SRSessionActivating) {
            if (![self validateIdentity:&error]) { [self beginClose:error]; [self advanceClose]; }
            return;
        }
        if (_policy.phase == SRSessionWaitingLayers || _policy.phase == SRSessionAttached) {
            if (![self refresh:NO error:&error]) { [self beginClose:error]; [self advanceClose]; return; }
            if (_policy.phase == SRSessionWaitingLayers && _container &&
                SRSessionPolicyAttach(&_policy, _policy.generation)) {
                // Actual checked host views are attached, not an empty placeholder.
                [self deliverStart:nil];
                dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC),
                                          200 * NSEC_PER_MSEC, 20 * NSEC_PER_MSEC);
            }
        }
    } @catch (NSException *exception) {
        (void)exception;
        [self beginClose:SRError(SRSceneSessionErrorException, @"Scene/layer operation raised; only owned resources will be cleaned up.")];
        [self advanceClose];
    }
}
- (void)refreshLayersWithCompletion:(SRSceneSessionCompletion)completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_policy.phase != SRSessionAttached) {
            SRDeliver(completion, SRError(SRSceneSessionErrorInvalidState, @"Only an attached session can refresh.")); return;
        }
        NSError *error = nil;
        @try {
            if (![self refresh:YES error:&error]) { [self beginClose:error]; [self advanceClose]; }
        } @catch (NSException *exception) {
            (void)exception;
            error = SRError(SRSceneSessionErrorException, @"Explicit layer refresh raised.");
            [self beginClose:error]; [self advanceClose];
        }
        SRDeliver(completion, error);
    });
}
- (void)setContentBounds:(CGRect)bounds displayTransform:(CGAffineTransform)transform
             completion:(SRSceneSessionCompletion)completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSError *error = nil;
        if (!SRGeometry(bounds, transform)) {
            SRDeliver(completion, SRError(SRSceneSessionErrorInvalidInput, @"Display geometry must be finite, positive and invertible.")); return;
        }
        if (self->_policy.phase != SRSessionAttached) {
            SRDeliver(completion, SRError(SRSceneSessionErrorInvalidState, @"Only an attached session can change display geometry.")); return;
        }
        @try {
            if ([self validateIdentity:&error]) {
                self->_contentBounds = bounds; self->_transform = transform;
                if (![self refresh:YES error:&error]) { [self beginClose:error]; [self advanceClose]; }
            } else { [self beginClose:error]; [self advanceClose]; }
        } @catch (NSException *exception) {
            (void)exception;
            error = SRError(SRSceneSessionErrorException, @"Display update raised.");
            [self beginClose:error]; [self advanceClose];
        }
        SRDeliver(completion, error);
    });
}
- (void)beginClose:(NSError *)reason {
    if (_policy.phase == SRSessionClosed) return;
    if (reason && !_terminalError) _terminalError = reason;
    if (_policy.phase == SRSessionClosing) return;
    if (!SRSessionPolicyBeginClose(&_policy, CACurrentMediaTime(), 2.0)) return;
    if (reason && _invalidationHandler) {
        SRSceneSessionCompletion invalidated = _invalidationHandler;
        _invalidationHandler = nil;
        SRDeliver(invalidated, reason);
    }
    _keepAlive = self;
    // Generation invalidation happens BEFORE any UIKit teardown or callback.
    [_layersHost closeWithError:NULL]; _layersHost = nil; _layers = nil;
    [_container removeFromSuperview]; _container = nil; _target = nil;
    [self deliverStart:reason ?: SRError(SRSceneSessionErrorCancelled, @"Session closed before start completed.")];
    [self startTimer];
    dispatch_source_set_timer(_timer, DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC, 5 * NSEC_PER_MSEC);
}
- (void)advanceClose {
    if (_policy.phase != SRSessionClosing) return;
    @try {
        BOOL identity = NO, foreground = NO, proof = NO;
        NSError *error = nil;
        if (_policy.foreground == SRSessionForegroundOwned) {
            identity = [self validateIdentity:&error];
            if (identity && !SRFreshSettings(_scene, &foreground, &error)) identity = NO;
            proof = identity && _lease && _lease.scene == _scene &&
                [_lease.sceneIdentifier isEqualToString:_identifier] && _lease.ownsForegroundChange;
        }
        SRSessionRollback action = SRSessionPolicyRollback(&_policy, CACurrentMediaTime(), identity, foreground, proof);
        switch (action) {
            case SRSessionRollbackWait: return;
            case SRSessionRollbackFinish:
                if (_policy.foreground == SRSessionForegroundOwned)
                    SRSessionPolicyObserveForegroundAbsent(&_policy, identity);
                [self finishCloseUnresolved:NO]; return;
            case SRSessionRollbackUnresolved:
                [self finishCloseUnresolved:YES]; return;
            case SRSessionRollbackRestore: break;
        }
        if (![self beginGuardRestoring:YES error:&error]) { [self finishCloseUnresolved:YES]; return; }
        id settings = SRFreshSettings(_scene, &foreground, &error);
        if (!settings || ![self validateIdentity:&error]) { [self finishCloseUnresolved:YES]; return; }
        if (!foreground) {
            // No compensating write is needed; another actor already set NO.
            SRSessionPolicyObserveForegroundAbsent(&_policy, true);
            [self finishCloseUnresolved:NO]; return;
        }
        if (![self sendSettings:settings restoring:YES error:&error]) [self finishCloseUnresolved:YES];
    } @catch (NSException *exception) {
        (void)exception;
        [self finishCloseUnresolved:YES];
    }
}
- (void)finishCloseUnresolved:(BOOL)unresolved {
    if (_policy.phase != SRSessionClosing) return;
    if (!SRSessionPolicyFinishClose(&_policy, unresolved)) {
        unresolved = YES;
        SRSessionPolicyFinishClose(&_policy, true);
    }
    if (unresolved) {
        _closeError = SRError(SRSceneSessionErrorRollbackUnresolved,
            @"Owned views detached; remote foreground restoration is unproved, timed out, superseded, or unsafe because this scene is frontmost. No blind rollback was sent.");
        if (!_terminalError) _terminalError = _closeError;
    }
    if (_timer) { dispatch_source_cancel(_timer); _timer = nil; }
    @try { [_lease invalidateWithoutMutation]; }
    @catch (NSException *exception) {
        (void)exception;
        _closeError = SRError(SRSceneSessionErrorRollbackUnresolved, @"Local foreground lease release failed; no further private call will be attempted.");
        if (!_terminalError) _terminalError = _closeError;
    }
    _guardOpen = NO; _lease = nil;
    _invalidationHandler = nil;
    _scene = nil; _manager = nil; _authority = nil;
    // Keep _identifier for diagnostics, but no borrowed pointer/layer survives.
    if (SRSessionPolicyTakeCloseCompletion(&_policy)) {
        NSArray<SRSceneSessionCompletion> *callbacks = [_closeCompletions copy];
        [_closeCompletions removeAllObjects];
        for (SRSceneSessionCompletion callback in callbacks) SRDeliver(callback, _closeError);
    }
    _keepAlive = nil;
}
- (void)requestClose:(NSError *)reason completion:(SRSceneSessionCompletion)completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_policy.phase == SRSessionClosed) { SRDeliver(completion, self->_closeError); return; }
        if (completion) [self->_closeCompletions addObject:[completion copy]];
        [self beginClose:reason];
        [self advanceClose];
    });
}
- (void)cancelWithCompletion:(SRSceneSessionCompletion)completion {
    [self requestClose:SRError(SRSceneSessionErrorCancelled, @"Session cancelled; pending attachment generation invalidated.") completion:completion];
}
- (void)closeWithCompletion:(SRSceneSessionCompletion)completion {
    [self requestClose:nil completion:completion];
}
- (void)dealloc {
    // Admitted sessions self-hold until bounded close. This path is for an idle
    // or already closed token; no private call/remote rollback from dealloc.
    if (_timer) dispatch_source_cancel(_timer);
}
@end
