#import <UIKit/UIKit.h>

FOUNDATION_EXPORT NSString *const WGPreferencesChanged;
FOUNDATION_EXPORT NSString *const WGRequestRetry;
FOUNDATION_EXPORT BOOL WGEnabled(void);
FOUNDATION_EXPORT BOOL WGExcludeSystemUsers(void);
FOUNDATION_EXPORT BOOL WGDebugEnabled(void);
FOUNDATION_EXPORT void WGSetEnabled(BOOL enabled);
FOUNDATION_EXPORT void WGRecordStatus(NSString *key, NSString *message);
FOUNDATION_EXPORT NSString *WGDiagnostics(void);
FOUNDATION_EXPORT void WGAttachSettingsEntry(UIViewController *controller);
FOUNDATION_EXPORT void WGPresentSettings(UIViewController *controller);

@interface WGSettingsController : UITableViewController
- (void)dismissSettings;
@end
