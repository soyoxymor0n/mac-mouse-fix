//
// --------------------------------------------------------------------------
// RemapTableDataSource.h
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Created by Noah Nuebling in 2021
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// This class used to be part of RemapTableController but it got pretty big so we split it in two.
/// This is basically a Utiliy class used by RemapTableController which helps translaate between the tableView dataModel and the strings and menus, etc displayed by the tableView
@interface RemapTableTranslator : NSObject <NSTableViewDataSource>

+ (void)initializeWithTableView:(NSTableView *)tableView;

+ (NSDictionary * _Nullable)getEntryFromEffectTable:(NSArray *)effectsTable withEffectDict:(NSDictionary *)effectDict;
//+ (NSDictionary *)getEntryFromEffectsTable:(NSArray *)effectsTable withUIString:(NSString *)uiString;
+ (NSArray *)getEffectsTableForRemapsTableEntry:(NSDictionary *)tableEntry;

+ (NSTableCellView *)getTriggerCellWithRowDict:(NSDictionary *)rowDict row:(NSInteger)row;
+ (NSTableCellView *)getEffectCellWithRowDict:(NSDictionary *)rowDict row:(NSUInteger)row tableViewEnabled:(BOOL)tableViewEnabled;

/// Fills the trigger dropdown of a button trigger row. Called right before the dropdown opens.
+ (void)fillTriggerMenu:(NSMenu *)menu forRowDict:(NSDictionary *)rowDict host:(NSTableCellView *)host;

/// Menu for adding a shortcut of the library (an entry from `ShortcutLibrary overviewEntriesForBundleID:`) to the tab of an app. Each item's representedObject has `trigger`, `bundleID` and `entry`.
+ (NSMenu *)addMenuForBundleID:(NSString *)bundleID entry:(NSDictionary *)entry target:(id)target action:(SEL)action;


+ (NSMenuItem * _Nullable)getPopUpButtonItemToSelectBasedOnRowDict:(NSPopUpButton * _Nonnull)button rowDict:(NSDictionary * _Nonnull)rowDict;
+ (NSDictionary * _Nullable)getEffectDictBasedOnSelectedItemInButton:(NSPopUpButton * _Nonnull)button rowDict:(NSDictionary * _Nonnull)rowDict;

@end

NS_ASSUME_NONNULL_END
