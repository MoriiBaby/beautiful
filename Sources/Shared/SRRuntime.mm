#import "SRRuntime.h"
#import "SRPolicy.h"
#import <mach-o/dyld.h>
#import <roothide.h>
#import <substrate.h>
#include <stdlib.h>
#include <string.h>

NSString *SRRootPath(NSString *path) {
    if (![path isKindOfClass:NSString.class] || !path.isAbsolutePath) return nil;
    return jbroot(path);
}
BOOL SRIsOriginalLoaded(void) {
    for (uint32_t i = 0; i < _dyld_image_count(); ++i) {
        const char *image = _dyld_get_image_name(i);
        if (!image) continue;
        const char *last = strrchr(image, '/');
        const char *name = last ? last + 1 : image;
        if (strcmp(name, "Stheno.dylib") == 0 || strcmp(name, "SthenoCamera.dylib") == 0 ||
            strcmp(name, "SthenoKeyboard.dylib") == 0) return YES;
    }
    return NSClassFromString(@"_TtC6Stheno12SthenoWindow") != Nil;
}
BOOL SRRuntimeCanActivate(void) {
    if (SRIsOriginalLoaded()) return NO;
    NSString *path = SRRootPath(@"/var/mobile/Library/Preferences/com.local.stheno.reconstruction.plist");
    if (!path) return NO;
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:path];
    id enabled = settings[@"EnableReconstruction"];
    return [enabled isKindOfClass:NSNumber.class] && [enabled boolValue];
}
BOOL SRCheckHookSignature(Class target, SEL selector, const char *expectedReturn,
                         const char * const *expectedArguments, size_t argumentCount) {
    if (!target || !selector || !expectedReturn || (argumentCount && !expectedArguments)) return NO;
    Method method = class_getInstanceMethod(target, selector);
    if (!method || method_getNumberOfArguments(method) != argumentCount + 2) return NO;
    char *result = method_copyReturnType(method);
    BOOL valid = SRTypeEncodingMatches(result, expectedReturn);
    free(result);
    char *receiver = method_copyArgumentType(method, 0);
    char *cmd = method_copyArgumentType(method, 1);
    valid = valid && (SRTypeEncodingMatches(receiver, "@") || SRTypeEncodingMatches(receiver, "#"))
        && SRTypeEncodingMatches(cmd, ":");
    free(receiver); free(cmd);
    for (size_t i = 0; valid && i < argumentCount; ++i) {
        char *actual = method_copyArgumentType(method, (unsigned)i + 2);
        valid = SRTypeEncodingMatches(actual, expectedArguments[i]);
        free(actual);
    }
    return valid;
}
BOOL SRInstallHook(Class target, SEL selector, IMP replacement, IMP *original,
                   const char *expectedReturn, const char * const *expectedArguments,
                   size_t argumentCount) {
    if (!replacement || !original || *original || !SRCheckHookSignature(target, selector,
        expectedReturn, expectedArguments, argumentCount)) return NO;
    MSHookMessageEx(target, selector, replacement, original);
    // Substrate has a void API; nonnull original only proves capture, not full behavior.
    return *original != NULL;
}
