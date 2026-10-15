#import "WGGroups.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

NSString *const WGGroupConfigsChanged = @"WGExtractor.GroupConfigsChanged";
static NSString *const kConfigs = @"WPGroupConfigs_v2";
static NSString *const kLast = @"WPPulse_LastGroup";
static NSMutableArray<NSMutableDictionary *> *gGroups;
static NSString *gCurrent;

static NSDictionary *Defaults(void) {
    return @{\
      @"name": @"全部", @"visible": @YES, @"isCustom": @NO, @"members": @[], @"type": @"all"};
}
static NSDictionary *FriendDefaults(void) {
    return @{\
      @"name": @"好友", @"visible": @YES, @"isCustom": @NO, @"members": @[], @"type": @"friends"};
}
static NSDictionary *GroupDefaults(void) {
    return @{\
      @"name": @"群聊", @"visible": @YES, @"isCustom": @NO, @"members": @[], @"type": @"groups"};
}
static NSDictionary *OfficialDefaults(void) {
    return @{\
      @"name": @"公众号", @"visible": @YES, @"isCustom": @NO, @"members": @[], @"type": @"official"};
}
static NSDictionary *UnreadDefaults(void) {
    return @{@"name": @"未读", @"visible": @YES, @"isCustom": @NO, @"members": @[], @"type": @"unread"};
}
static void EnsureLoaded(void) {
    if (gGroups) return;
    NSArray *saved = [[NSUserDefaults standardUserDefaults] objectForKey:kConfigs];
    gGroups = [NSMutableArray array];
    if ([saved isKindOfClass:NSArray.class]) {
        for (id item in saved) if ([item isKindOfClass:NSDictionary.class] && [item[@"name"] isKindOfClass:NSString.class]) {
            NSMutableDictionary *copy = [item mutableCopy];
            copy[@"visible"] = @([copy[@"visible"] boolValue]);
            copy[@"isCustom"] = @([copy[@"isCustom"] boolValue]);
            copy[@"members"] = [copy[@"members"] isKindOfClass:NSArray.class] ? [copy[@"members"] copy] : @[];
            if (!copy[@"type"]) copy[@"type"] = [copy[@"isCustom"] boolValue] ? @"custom" : @"all";
            [gGroups addObject:copy];
        }
    }
    if (!gGroups.count) [gGroups addObjectsFromArray:@[[Defaults() mutableCopy], [UnreadDefaults() mutableCopy], [FriendDefaults() mutableCopy], [GroupDefaults() mutableCopy], [OfficialDefaults() mutableCopy]]];
    NSMutableSet *names = [NSMutableSet set]; NSMutableArray *unique = [NSMutableArray array];
    for (NSMutableDictionary *g in gGroups) { if (![names containsObject:g[@"name"]]) { [names addObject:g[@"name"]]; [unique addObject:g]; } }
    gGroups = unique;
    NSString *last = [[NSUserDefaults standardUserDefaults] stringForKey:kLast];
    gCurrent = [names containsObject:last] ? [last copy] : @"全部";
}
static void Save(void) {
    EnsureLoaded();
    [[NSUserDefaults standardUserDefaults] setObject:gGroups forKey:kConfigs];
    if (gCurrent) [[NSUserDefaults standardUserDefaults] setObject:gCurrent forKey:kLast];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:WGGroupConfigsChanged object:nil];
}
NSArray<NSDictionary *> *WGGroupConfigs(void) { EnsureLoaded(); return [gGroups copy]; }
NSArray<NSDictionary *> *WGActiveGroupConfigs(void) { EnsureLoaded(); NSMutableArray *a=[NSMutableArray array]; for (NSDictionary *g in gGroups) if ([g[@"visible"] boolValue]) [a addObject:[g copy]]; return a; }
NSString *WGCurrentGroupName(void) { EnsureLoaded(); return gCurrent ?: @"全部"; }
void WGSelectGroupName(NSString *name) { EnsureLoaded(); for (NSDictionary *g in gGroups) if ([g[@"name"] isEqualToString:name] && [g[@"visible"] boolValue]) { gCurrent=[name copy]; [[NSUserDefaults standardUserDefaults] setObject:gCurrent forKey:kLast]; return; } }
NSString *WGGroupNameForIndex(NSUInteger index) { NSArray *a=WGActiveGroupConfigs(); return index<a.count ? a[index][@"name"] : nil; }
NSString *WGSessionUsername(id session) {
    if (!session) return nil;
    for (NSString *key in @[@"m_nsUserName", @"m_nsUsrName", @"userName"]) {
        @try { id v=[session valueForKey:key]; if ([v isKindOfClass:NSString.class] && [v length]) return v; } @catch (__unused NSException *e) {}
        Ivar ivar=class_getInstanceVariable(object_getClass(session), key.UTF8String); if (ivar) { id v=object_getIvar(session,ivar); if ([v isKindOfClass:NSString.class] && v) return v; }
    }
    return nil;
}
NSUInteger WGSessionUnreadCount(id session) {
    for (NSString *key in @[@"m_uUnReadCount", @"unreadCount"]) { @try { id v=[session valueForKey:key]; if ([v respondsToSelector:@selector(unsignedIntegerValue)]) return [v unsignedIntegerValue]; } @catch (__unused NSException *e) {} }
    return 0;
}
BOOL WGGroupMatchesSession(id session, NSString *name) {
    NSDictionary *g=WGConfigForGroup(name); if (!g) return NO;
    NSString *u=WGSessionUsername(session) ?: @""; NSString *type=g[@"type"] ?: @"all";
    if ([type isEqualToString:@"all"]) return YES;
    if ([type isEqualToString:@"unread"]) return WGSessionUnreadCount(session)>0;
    if ([type isEqualToString:@"groups"]) return [u hasSuffix:@"@chatroom"];
    if ([type isEqualToString:@"official"]) return [u hasPrefix:@"gh_"] || [u isEqualToString:@"brandsessionholder"];
    if ([type isEqualToString:@"friends"]) return u.length && ![u hasSuffix:@"@chatroom"] && ![u hasPrefix:@"gh_"] && [u rangeOfString:@"@"].location==NSNotFound && ![[@"newsapp weixin filehelper notification_messages fmessage medianote floatbottle qmessage tmessage qqmail masssendapp feedsapp shakeapp voipapp readerapp linkedinplugin" componentsSeparatedByString:@" "] containsObject:u];
    if ([type isEqualToString:@"custom"]) return [g[@"members"] containsObject:u];
    return NO;
}
NSDictionary *WGConfigForGroup(NSString *name) { EnsureLoaded(); for (NSDictionary *g in gGroups) if ([g[@"name"] isEqualToString:name]) return g; return nil; }
BOOL WGGroupIsCustom(NSString *n){return [WGConfigForGroup(n)[@"isCustom"] boolValue];}
BOOL WGGroupUsesUnread(NSString *n){return [WGConfigForGroup(n)[@"type"] isEqualToString:@"unread"];}
BOOL WGGroupUsesFriends(NSString *n){return [WGConfigForGroup(n)[@"type"] isEqualToString:@"friends"];}
BOOL WGGroupUsesChatrooms(NSString *n){return [WGConfigForGroup(n)[@"type"] isEqualToString:@"groups"];}
BOOL WGGroupUsesOfficial(NSString *n){return [WGConfigForGroup(n)[@"type"] isEqualToString:@"official"];}
BOOL WGSetGroupVisible(NSString *name, BOOL visible) { EnsureLoaded(); if ([name isEqualToString:@"全部"]) return NO; for (NSMutableDictionary *g in gGroups) if ([g[@"name"] isEqualToString:name]) { g[@"visible"]=@(visible); if (!visible && [gCurrent isEqualToString:name]) gCurrent=@"全部"; Save(); return YES; } return NO; }
BOOL WGRenameGroup(NSString *name, NSString *newName) { EnsureLoaded(); if (!newName.length || WGConfigForGroup(newName)) return NO; for (NSMutableDictionary *g in gGroups) if ([g[@"name"] isEqualToString:name] && ![name isEqualToString:@"全部"]) { g[@"name"]=[newName copy]; if ([gCurrent isEqualToString:name]) gCurrent=[newName copy]; Save(); return YES; } return NO; }
BOOL WGMoveGroup(NSString *name, BOOL forward) { EnsureLoaded(); NSUInteger i=NSNotFound; for(NSUInteger n=0;n<gGroups.count;n++) if([gGroups[n][@"name"] isEqualToString:name]) {i=n;break;} if(i==NSNotFound || (forward && i+1>=gGroups.count) || (!forward && i==0))return NO; NSUInteger j=forward?i+1:i-1; [gGroups exchangeObjectAtIndex:i withObjectAtIndex:j]; Save(); return YES; }
BOOL WGDeleteCustomGroup(NSString *name) { EnsureLoaded(); if(!WGGroupIsCustom(name))return NO; for(NSUInteger i=0;i<gGroups.count;i++)if([gGroups[i][@"name"] isEqualToString:name]){[gGroups removeObjectAtIndex:i];if([gCurrent isEqualToString:name])gCurrent=@"全部";Save();return YES;}return NO; }
BOOL WGCreateCustomGroup(NSString *name, NSArray<NSString *> *members) { EnsureLoaded(); if(!name.length || WGConfigForGroup(name))return NO; [gGroups addObject:[@{ @"name":name, @"visible":@YES, @"isCustom":@YES, @"type":@"custom", @"members":members ?: @[]} mutableCopy]]; Save(); return YES; }
BOOL WGSetGroupMembers(NSString *name, NSArray<NSString *> *members) { EnsureLoaded(); for(NSMutableDictionary*g in gGroups)if([g[@"name"] isEqualToString:name]&&[g[@"isCustom"] boolValue]){g[@"members"]=members?:@[];Save();return YES;}return NO; }
void WGResetGroupConfigs(void) { gGroups=nil;gCurrent=nil;[[NSUserDefaults standardUserDefaults] removeObjectForKey:kConfigs];[[NSUserDefaults standardUserDefaults] removeObjectForKey:kLast];EnsureLoaded();Save(); }
