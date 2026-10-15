#import <UIKit/UIKit.h>
FOUNDATION_EXPORT BOOL WGSettingBool(NSString *key, BOOL fallback);
FOUNDATION_EXPORT void WGSetSettingBool(NSString *key, BOOL value);
FOUNDATION_EXPORT CGFloat WGSettingFloat(NSString *key, CGFloat fallback);
FOUNDATION_EXPORT void WGSetSettingFloat(NSString *key, CGFloat value);
FOUNDATION_EXPORT UIColor *WGSettingColor(NSString *key, UIColor *fallback);
FOUNDATION_EXPORT void WGSetSettingColor(NSString *key, UIColor *value);
FOUNDATION_EXPORT NSInteger WGHapticLevel(void);
FOUNDATION_EXPORT BOOL WGLoopSwipe(void);
FOUNDATION_EXPORT BOOL WGReverseSwipe(void);
FOUNDATION_EXPORT BOOL WGHideSideDock(void);
FOUNDATION_EXPORT BOOL WGFixedSideDock(void);
FOUNDATION_EXPORT BOOL WGHideTopBar(void);
FOUNDATION_EXPORT BOOL WGHideTopBadges(void);
FOUNDATION_EXPORT BOOL WGHideDockBadges(void);
FOUNDATION_EXPORT CGFloat WGTopMargin(void);
FOUNDATION_EXPORT CGFloat WGDockPosition(void);
FOUNDATION_EXPORT NSString *const WGAppearanceChanged;
