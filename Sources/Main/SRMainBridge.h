#pragma once
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// C bridge names are stable in Swift; these calls never install hooks or create scenes by themselves.
FOUNDATION_EXPORT BOOL SRMainSceneHostingAvailable(void);
FOUNDATION_EXPORT NSString * _Nonnull SRMainSceneHostingBlocker(void);
FOUNDATION_EXPORT id _Nonnull SRMainCreateSceneSession(void);
FOUNDATION_EXPORT BOOL SRMainAttachScene(id _Nonnull session, NSString * _Nonnull bundleID,
    UIView * _Nonnull target, NSError * _Nullable * _Nullable error);
FOUNDATION_EXPORT BOOL SRMainResizeScene(id _Nonnull session, CGRect bounds,
    NSError * _Nullable * _Nullable error);
FOUNDATION_EXPORT BOOL SRMainCloseScene(id _Nonnull session, NSError * _Nullable * _Nullable error);
