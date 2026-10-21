#pragma once
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// C bridge names are stable in Swift; these calls never install hooks or create scenes by themselves.
FOUNDATION_EXPORT BOOL SRMainSceneHostingAvailable(void);
FOUNDATION_EXPORT NSString * _Nonnull SRMainSceneHostingBlocker(void);
FOUNDATION_EXPORT id _Nonnull SRMainCreateSceneSession(void);
typedef void (^SRMainCompletion)(NSError * _Nullable error);
FOUNDATION_EXPORT void SRMainAttachSceneAsync(id _Nonnull session, NSString * _Nonnull bundleID,
    UIView * _Nonnull target, SRMainCompletion _Nonnull completion);
FOUNDATION_EXPORT void SRMainResizeSceneAsync(id _Nonnull session, CGRect bounds,
    SRMainCompletion _Nonnull completion);
FOUNDATION_EXPORT void SRMainCloseSceneAsync(id _Nonnull session, SRMainCompletion _Nonnull completion);
FOUNDATION_EXPORT void SRMainSetInvalidationHandler(id _Nonnull session, SRMainCompletion _Nonnull handler);
FOUNDATION_EXPORT BOOL SRMainConstrainWindow(CGRect requested, CGRect screen, CGRect * _Nonnull result);
