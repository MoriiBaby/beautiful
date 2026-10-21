#import "SRLayerHostCandidate.h"
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#include <cmath>
#include <cstdlib>
#include <cstring>

#if !__has_feature(objc_arc)
#error SRLayerHostCandidate requires ARC
#endif

NSErrorDomain const SRLayerHostCandidateErrorDomain = @"com.local.stheno.layer-host-lab";

// Ownership is part of the callable type. Casting init to ordinary id(*)(...)
// would lose both the consumed receiver and retained result under ARC.
typedef id _Nullable (*SRLabAlloc)(id receiver, SEL command)
    __attribute__((ns_returns_retained));
typedef id _Nullable (*SRLabInitOne)(id __attribute__((ns_consumed)) receiver,
                                    SEL command, id layer)
    __attribute__((ns_returns_retained));
typedef id _Nullable (*SRLabInitTwo)(id __attribute__((ns_consumed)) receiver,
                                    SEL command, id layer, id scene)
    __attribute__((ns_returns_retained));
typedef BOOL (*SRLabKeyboardGetter)(id receiver, SEL command);

static BOOL SRLabFail(NSError **error, SRLayerHostCandidateError code, NSString *message) {
    if (error) *error = [NSError errorWithDomain:SRLayerHostCandidateErrorDomain code:code
                                      userInfo:@{NSLocalizedDescriptionKey: message}];
    return NO;
}

static BOOL SRLabMain(NSError **error) {
    return [NSThread isMainThread] || SRLabFail(error, SRLayerHostCandidateErrorMainThread,
                                               @"Layer-host lab operations require the main thread.");
}

// Accept exactly an object ABI, never @? / pointers / integers. If runtime
// metadata supplies a class name, enforce THAT class, not a guessed wider id.
// No FBSSceneLayer class name is invented: the original stores opaque objects.
static BOOL SRLabObjectType(const char *type, Class *namedClass) {
    *namedClass = Nil;
    if (!type) return NO;
    if (strcmp(type, "@") == 0) return YES;
    const size_t count = strlen(type);
    if (count < 4 || type[0] != '@' || type[1] != '"' || type[count - 1] != '"') return NO;
    NSString *name = [[NSString alloc] initWithBytes:type + 2 length:count - 3
                                           encoding:NSUTF8StringEncoding];
    // Protocol-qualified, malformed or unresolved class metadata is rejected.
    if (!name.length || [name rangeOfCharacterFromSet:
        [NSCharacterSet characterSetWithCharactersInString:@"<>\"\\"]].location != NSNotFound) return NO;
    *namedClass = NSClassFromString(name);
    return *namedClass != Nil;
}

// Resolve and call the SAME checked IMP, rather than checking an encoding then
// doing a second dispatch that might resolve to a different implementation.
// Explicit arguments are opaque objects, constrained by actual class metadata.
static BOOL SRLabCheckedIMP(id receiver, SEL selector, BOOL objectResult,
                            id const *arguments, unsigned count, IMP *implementation,
                            Class *returnClass, NSError **error) {
    Class actual = receiver ? object_getClass(receiver) : Nil;
    Method method = actual ? class_getInstanceMethod(actual, selector) : NULL;
    BOOL valid = method && method_getNumberOfArguments(method) == count + 2;
    char *type = method ? method_copyReturnType(method) : NULL;
    *returnClass = Nil;
    valid = valid && (objectResult ? SRLabObjectType(type, returnClass)
                                 : type && strcmp(type, @encode(BOOL)) == 0);
    free(type);
    for (unsigned index = 0; valid && index < count + 2; ++index) {
        type = method_copyArgumentType(method, index);
        if (index == 0) {
            valid = type && (strcmp(type, "@") == 0 ||
                     (class_isMetaClass(actual) && strcmp(type, "#") == 0));
        } else if (index == 1) {
            valid = type && strcmp(type, ":") == 0;
        } else {
            Class parameterClass = Nil;
            id argument = arguments[index - 2];
            valid = SRLabObjectType(type, &parameterClass) && argument &&
                    (!parameterClass || [argument isKindOfClass:parameterClass]);
        }
        free(type);
    }
    *implementation = valid ? method_getImplementation(method) : NULL;
    if (!*implementation) {
        return SRLabFail(error, SRLayerHostCandidateErrorRuntimeABI,
                         [NSString stringWithFormat:@"Rejected runtime ABI for %@.%@",
                          actual ? NSStringFromClass(actual) : @"nil", NSStringFromSelector(selector)]);
    }
    return YES;
}

static BOOL SRLabReturnMatches(id value, Class declared, Class required) {
    return value && [value isKindOfClass:required] &&
           (!declared || [value isKindOfClass:declared]);
}

static UIView *SRLabConstructView(Class hostClass, id layer, id scene,
                                  BOOL keyboard, NSError **error) {
    if (!hostClass || ![hostClass isSubclassOfClass:UIView.class]) {
        SRLabFail(error, SRLayerHostCandidateErrorRuntimeABI, @"Private layer-host UIView class is absent.");
        return nil;
    }
    IMP implementation = NULL;
    Class declared = Nil;
    const SEL allocSelector = @selector(alloc);
    if (!SRLabCheckedIMP(hostClass, allocSelector, YES, NULL, 0,
                         &implementation, &declared, error)) return nil;
    id allocation = ((SRLabAlloc)implementation)(hostClass, allocSelector);
    if (!SRLabReturnMatches(allocation, declared, hostClass)) {
        SRLabFail(error, SRLayerHostCandidateErrorConstruction, @"Unexpected alloc result.");
        return nil;
    }
    const SEL initSelector = NSSelectorFromString(keyboard ? @"initWithKeyboardLayer:owningScene:"
                                                           : @"initWithSceneLayer:");
    id arguments[2] = {layer, scene};
    if (!SRLabCheckedIMP(allocation, initSelector, YES, arguments, keyboard ? 2 : 1,
                         &implementation, &declared, error)) return nil;
    // Both casts carry ns_consumed + ns_returns_retained. No performSelector,
    // unmanaged bridge, untyped init send, copied PAC bits or manual release.
    id result = keyboard
        ? ((SRLabInitTwo)implementation)(allocation, initSelector, layer, scene)
        : ((SRLabInitOne)implementation)(allocation, initSelector, layer);
    if (!SRLabReturnMatches(result, declared, hostClass)) {
        SRLabFail(error, SRLayerHostCandidateErrorConstruction, @"Private init did not return the checked UIView class.");
        return nil;
    }
    UIView *view = result;
    if (view.superview || view.window) {
        SRLabFail(error, SRLayerHostCandidateErrorConstruction, @"Private init returned an already-attached view; ownership refused.");
        return nil;
    }
    return view;
}

static void SRLabRemoveViews(NSArray<UIView *> *hosts, NSArray<UIView *> *keyboards) {
    for (UIView *view in hosts) [view removeFromSuperview];
    for (UIView *view in keyboards) [view removeFromSuperview];
}

@interface SRLayerHostCandidate ()
@property (nonatomic, copy, readwrite) NSArray<UIView *> *hostViews;
@property (nonatomic, copy, readwrite) NSArray<UIView *> *keyboardViews;
@end

@implementation SRLayerHostCandidate {
    id _borrowedScene;
    NSArray *_retainedLayers;
}
+ (BOOL)isLabEnabled { return SR_ENABLE_LAYER_HOST_LAB == 1; }
- (instancetype)init {
    self = [super init];
    if (self) { _hostViews = @[]; _keyboardViews = @[]; _retainedLayers = @[]; }
    return self;
}
- (BOOL)isPrepared { return _borrowedScene != nil && (_hostViews.count + _keyboardViews.count) != 0; }

- (BOOL)rebuildForBorrowedScene:(id)scene clientLayers:(NSOrderedSet *)layers error:(NSError **)error {
    if (error) *error = nil;
    if (!SRLabMain(error)) return NO;
    if (!SRLayerHostCandidate.labEnabled)
        return SRLabFail(error, SRLayerHostCandidateErrorDisabled, @"Layer-host lab is disabled at build time.");
    Class sceneClass = NSClassFromString(@"FBScene");
    if (!sceneClass || ![scene isKindOfClass:sceneClass] ||
        ![layers isKindOfClass:NSOrderedSet.class] || layers.count == 0) {
        return SRLabFail(error, SRLayerHostCandidateErrorInvalidInput,
                         @"Supply a borrowed FBScene and a nonempty ordered layer set.");
    }
    NSArray *retained = [layers.array copy];
    NSMutableArray<UIView *> *hosts = [NSMutableArray array];
    NSMutableArray<UIView *> *keyboards = [NSMutableArray array];
    @try {
        for (id layer in retained) {
            IMP implementation = NULL;
            Class unusedReturn = Nil;
            SEL selector = NSSelectorFromString(@"isKeyboardLayer");
            if (!SRLabCheckedIMP(layer, selector, NO, NULL, 0, &implementation, &unusedReturn, error)) return NO;
            const BOOL keyboard = ((SRLabKeyboardGetter)implementation)(layer, selector);
            Class hostClass = NSClassFromString(keyboard ? @"_UIKeyboardLayerHostView" : @"_UIContextLayerHostView");
            UIView *view = SRLabConstructView(hostClass, layer, scene, keyboard, error);
            if (!view) return NO;
            // Original 65cd4 uses the actual UIView, not a replacement/snapshot.
            view.clipsToBounds = NO;
            [(keyboard ? keyboards : hosts) addObject:view];
        }
    } @catch (NSException *exception) {
        (void)exception;
        return SRLabFail(error, SRLayerHostCandidateErrorConstruction,
                         @"Private layer-host construction raised an exception; previous views kept.");
    }
    // All checked constructors succeeded. Release only our former views. Scene
    // and layers stay strongly referenced until their owned views are removed.
    NSArray *oldLayers = _retainedLayers;
    id oldScene = _borrowedScene;
    SRLabRemoveViews(_hostViews, _keyboardViews);
    self.hostViews = hosts;
    self.keyboardViews = keyboards;
    _retainedLayers = retained;
    _borrowedScene = scene;
    // Explicit lifetime fences, without sending any message to the scene/layers.
    id sceneFence __attribute__((objc_precise_lifetime)) = oldScene;
    NSArray *layerFence __attribute__((objc_precise_lifetime)) = oldLayers;
    (void)sceneFence; (void)layerFence;
    return YES;
}

- (BOOL)applyDisplayTransform:(CGAffineTransform)transform error:(NSError **)error {
    if (error) *error = nil;
    if (!SRLabMain(error)) return NO;
    if (!SRLayerHostCandidate.labEnabled)
        return SRLabFail(error, SRLayerHostCandidateErrorDisabled, @"Layer-host lab is disabled at build time.");
    const double determinant = transform.a * transform.d - transform.b * transform.c;
    if (!self.prepared || !std::isfinite(transform.a) || !std::isfinite(transform.b) ||
        !std::isfinite(transform.c) || !std::isfinite(transform.d) ||
        !std::isfinite(transform.tx) || !std::isfinite(transform.ty) ||
        !std::isfinite(determinant) || determinant == 0) {
        return SRLabFail(error, SRLayerHostCandidateErrorInvalidInput,
                         @"Prepared real views and a finite invertible display transform are required.");
    }
    for (UIView *view in _hostViews) view.transform = transform;
    for (UIView *view in _keyboardViews) view.transform = transform;
    return YES;
}

- (BOOL)closeWithError:(NSError **)error {
    if (error) *error = nil;
    if (!SRLabMain(error)) return NO;
    SRLabRemoveViews(_hostViews, _keyboardViews);
    self.hostViews = @[];
    self.keyboardViews = @[];
    _retainedLayers = @[];
    _borrowedScene = nil;
    return YES;
}

- (void)dealloc {
    if (_hostViews.count == 0 && _keyboardViews.count == 0) return;
    // Fallback for callers who fail to close on main. Capture no self. Keep the
    // entire owned set alive until main-thread removal, then release together.
    NSArray *owned = @[_hostViews, _keyboardViews, _retainedLayers, _borrowedScene ?: NSNull.null];
    if ([NSThread isMainThread]) {
        SRLabRemoveViews(owned[0], owned[1]);
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{ SRLabRemoveViews(owned[0], owned[1]); });
    }
}
@end
