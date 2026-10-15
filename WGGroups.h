#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *const WGGroupConfigsChanged;
FOUNDATION_EXPORT NSArray<NSDictionary *> *WGGroupConfigs(void);
FOUNDATION_EXPORT NSArray<NSDictionary *> *WGActiveGroupConfigs(void);
FOUNDATION_EXPORT NSString *WGCurrentGroupName(void);
FOUNDATION_EXPORT void WGSelectGroupName(NSString *name);
FOUNDATION_EXPORT NSString *WGGroupNameForIndex(NSUInteger index);
FOUNDATION_EXPORT BOOL WGGroupMatchesSession(id session, NSString *name);
FOUNDATION_EXPORT NSString *WGSessionUsername(id session);
FOUNDATION_EXPORT NSUInteger WGSessionUnreadCount(id session);
FOUNDATION_EXPORT void WGResetGroupConfigs(void);
FOUNDATION_EXPORT BOOL WGSetGroupVisible(NSString *name, BOOL visible);
FOUNDATION_EXPORT BOOL WGRenameGroup(NSString *name, NSString *newName);
FOUNDATION_EXPORT BOOL WGMoveGroup(NSString *name, BOOL forward);
FOUNDATION_EXPORT BOOL WGDeleteCustomGroup(NSString *name);
FOUNDATION_EXPORT BOOL WGCreateCustomGroup(NSString *name, NSArray<NSString *> *members);
FOUNDATION_EXPORT BOOL WGSetGroupMembers(NSString *name, NSArray<NSString *> *members);
FOUNDATION_EXPORT NSDictionary *WGConfigForGroup(NSString *name);
FOUNDATION_EXPORT BOOL WGGroupIsCustom(NSString *name);
FOUNDATION_EXPORT BOOL WGGroupUsesUnread(NSString *name);
FOUNDATION_EXPORT BOOL WGGroupUsesFriends(NSString *name);
FOUNDATION_EXPORT BOOL WGGroupUsesChatrooms(NSString *name);
FOUNDATION_EXPORT BOOL WGGroupUsesOfficial(NSString *name);
