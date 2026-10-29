//
// --------------------------------------------------------------------------
// ScrollExcludedApps.h
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//

/// Matching logic for `Scroll.excludedApps`. Used by `Scroll.m`.
/// Kept free of global state so it can be unit tested on its own.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Returns YES if `bundleID` is one of the entries in `excludedBundleIDs`.
///     - Entries that are not strings are ignored. Passing nil for either argument returns NO.
///     - The comparison is case-insensitive, so hand-edited config entries still match.
static inline BOOL MFScrollAppIsExcluded(NSString * _Nullable bundleID, NSArray * _Nullable excludedBundleIDs) {

    if (![bundleID isKindOfClass:NSString.class] || ![excludedBundleIDs isKindOfClass:NSArray.class]) {
        return NO;
    }
    for (id entry in excludedBundleIDs) {
        if ([entry isKindOfClass:NSString.class]) {
            NSString *excludedID = entry;
            if ([bundleID caseInsensitiveCompare:excludedID] == NSOrderedSame) {
                return YES;
            }
        }
    }
    return NO;
}

NS_ASSUME_NONNULL_END
