#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN
// RootHide only. No mainBundle/.jbroot or absolute dlopen fallback.
FOUNDATION_EXPORT NSString * _Nullable SRRootPath(NSString *path);
FOUNDATION_EXPORT BOOL SRIsOriginalLoaded(void);
// Explicit opt-in in com.local.stheno.reconstruction.plist; default is NO.
FOUNDATION_EXPORT BOOL SRRuntimeCanActivate(void);
// expectedArguments excludes the two implicit self/_cmd arguments.
FOUNDATION_EXPORT BOOL SRCheckHookSignature(Class _Nullable target, SEL selector,
    const char *expectedReturn, const char * _Nonnull const * _Nullable expectedArguments,
    size_t argumentCount);
FOUNDATION_EXPORT BOOL SRInstallHook(Class _Nullable target, SEL selector,
    IMP replacement, IMP _Nullable * _Nonnull original, const char *expectedReturn,
    const char * _Nonnull const * _Nullable expectedArguments, size_t argumentCount);
NS_ASSUME_NONNULL_END
