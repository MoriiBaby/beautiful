#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "../Shared/SRRuntime.h"
#import "../Shared/SRPolicy.h"
#include <stdlib.h>

// Original: Camera arm64e 0x4048/0x4068 skip writes, 0x4078 stores; 0x412c reloads.
static bool gCameraEnabled = false;
static IMP gOriginalCamera = nullptr;
static void SRCameraReload(void) {
    NSString *path = SRRootPath(@"/var/mobile/Library/Preferences/com.nx.stheno.plist");
    if (!path) return;
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:path];
    id value = prefs[@"Camera"];
    // Missing dictionary/key retains state. Malformed values now fail closed to old state.
    if (!prefs || !value || ![value respondsToSelector:@selector(boolValue)]) return;
    const bool previous = __atomic_load_n(&gCameraEnabled, __ATOMIC_RELAXED);
    const bool next = SRStickyFlagNext(previous, true, true, [value boolValue]);
    __atomic_store_n(&gCameraEnabled, next, __ATOMIC_RELAXED);
}
template<typename Condition>
static void SRCameraUpdate(id receiver, SEL selector, Condition condition, id value) {
    SRCameraReload();
    if (__atomic_load_n(&gCameraEnabled, __ATOMIC_RELAXED)) return;
    auto original = reinterpret_cast<void (*)(id, SEL, Condition, id)>(gOriginalCamera);
    if (original) original(receiver, selector, condition, value);
}
template<typename Condition>
static bool SRCameraTryInstall(Class cls, SEL selector) {
    const char *arguments[] = {@encode(Condition), @encode(id)};
    if (!SRCheckHookSignature(cls, selector, @encode(void), arguments, 2)) return false;
    return SRInstallHook(cls, selector, (IMP)&SRCameraUpdate<Condition>, &gOriginalCamera,
                         @encode(void), arguments, 2);
}
__attribute__((constructor)) static void SRCameraInitialize(void) {
    @autoreleasepool {
        if (!SRRuntimeCanActivate()) return;
        Class cls = objc_getClass("FigCaptureClientSessionMonitor");
        SEL selector = sel_registerName("_updateClientStateCondition:newValue:");
        // x2 is not proven to be an object. Select only an EXACT runtime-verified ABI.
        // Each specialization is typed; unsupported encodings are deliberately not hooked.
        if (SRCameraTryInstall<long long>(cls, selector) ||
            SRCameraTryInstall<unsigned long long>(cls, selector) ||
            SRCameraTryInstall<int>(cls, selector) ||
            SRCameraTryInstall<unsigned int>(cls, selector) ||
            SRCameraTryInstall<bool>(cls, selector) ||
            SRCameraTryInstall<id>(cls, selector)) return;
        NSLog(@"[SthenoRebuildCamera] Unsupported or unavailable method ABI; hook disabled");
    }
}
