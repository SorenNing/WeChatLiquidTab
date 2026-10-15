#import "WGSettings.h"
#import "WGGroups.h"
#import <objc/runtime.h>

NSString *const WGPreferencesChanged = @"WGExtractor.PreferencesChanged";
NSString *const WGRequestRetry = @"WGExtractor.RequestRetry";
static NSString *const kEnabled = @"WGExtractor.Enabled";
static NSString *const kExcludeSystem = @"WGExtractor.ExcludeSystemUsers";
static NSString *const kDebug = @"WGExtractor.Debug";
static NSMutableDictionary<NSString *, NSString *> *gStatus;
static char kEntryTarget;

static BOOL WGReadBool(NSString *key, BOOL fallback) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id value = [defaults objectForKey:key];
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : fallback;
}
BOOL WGEnabled(void) { return WGReadBool(kEnabled, YES); }
BOOL WGExcludeSystemUsers(void) { return WGReadBool(kExcludeSystem, YES); }
BOOL WGDebugEnabled(void) { return WGReadBool(kDebug, NO); }

static void WGWriteBool(NSString *key, BOOL value) {
    [NSUserDefaults.standardUserDefaults setBool:value forKey:key];
    [NSNotificationCenter.defaultCenter postNotificationName:WGPreferencesChanged object:nil];
}
void WGSetEnabled(BOOL enabled) { WGWriteBool(kEnabled, enabled); }

void WGRecordStatus(NSString *key, NSString *message) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ WGRecordStatus(key, message); });
        return;
    }
    if (!gStatus) gStatus = [NSMutableDictionary dictionary];
    BOOL changed = ![gStatus[key] isEqualToString:message];
    gStatus[key] = message;
    // Status strings contain only compatibility/mount information, never session identities.
    if (changed && WGDebugEnabled()) NSLog(@"[WeChatGroupExtractor] %@: %@", key, message);
}

NSString *WGDiagnostics(void) {
    NSCAssert(NSThread.isMainThread, @"Diagnostics must be read on the main thread");
    NSBundle *bundle = NSBundle.mainBundle;
    NSString *version = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"未知";
    NSString *build = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"未知";
    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithArray:@[
        @"WeChatGroupExtractor 0.0.3",
        @"插件代码：已加载（能打开本页说明当前微信进程已加载插件）",
        [NSString stringWithFormat:@"微信版本：%@ (%@)", version, build],
        [NSString stringWithFormat:@"iOS：%@", UIDevice.currentDevice.systemVersion],
        [NSString stringWithFormat:@"分组开关：%@", WGEnabled() ? @"开启" : @"关闭"]]];
    for (NSString *key in [gStatus.allKeys sortedArrayUsingSelector:@selector(compare:)])
        [lines addObject:[NSString stringWithFormat:@"%@: %@", key, gStatus[key]]];
    [lines addObject:@"分类按用户名规则；不是好友关系数据库核验。"];
    [lines addObject:@"状态仅描述当前进程；不证明会话刷新或长期稳定性。"];
    return [lines componentsJoinedByString:@"\n"];
}

void WGPresentSettings(UIViewController *controller) {
    if (!controller || !controller.isViewLoaded || !controller.view.window) return;
    if ([controller isKindOfClass:WGSettingsController.class] ||
        [controller.navigationController.topViewController isKindOfClass:WGSettingsController.class]) return;
    if (controller.presentedViewController) return;
    WGSettingsController *settings = [WGSettingsController new];
    if (controller.navigationController) {
        [controller.navigationController pushViewController:settings animated:YES];
    } else {
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:settings];
        settings.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:settings action:@selector(dismissSettings)];
        [controller presentViewController:navigation animated:YES completion:nil];
    }
}

// The bar button retains its target via an association; the target only weakly owns the page.
@interface WGEntryTarget : NSObject
@property(nonatomic, weak) UIViewController *controller;
- (void)open;
@end
@implementation WGEntryTarget
- (void)open { WGPresentSettings(self.controller); }
@end

void WGAttachSettingsEntry(UIViewController *controller) {
    NSArray<UIBarButtonItem *> *items = controller.navigationItem.rightBarButtonItems ?: @[];
    for (UIBarButtonItem *item in items)
        if ([item.accessibilityIdentifier isEqualToString:@"WGExtractor.SettingsEntry"]) return;
    WGEntryTarget *target = [WGEntryTarget new];
    target.controller = controller;
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithTitle:@"分组设置"
        style:UIBarButtonItemStylePlain target:target action:@selector(open)];
    item.accessibilityIdentifier = @"WGExtractor.SettingsEntry";
    item.accessibilityLabel = @"WeChatGroupExtractor 分组设置";
    objc_setAssociatedObject(item, &kEntryTarget, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    controller.navigationItem.rightBarButtonItems = [@[item] arrayByAddingObjectsFromArray:items];
    WGRecordStatus(@"设置入口", @"已添加到微信设置页右上角");
}

@interface WGGroupManagerController : UITableViewController
@end
@implementation WGGroupManagerController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"分组管理"; self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addGroup)]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return WGGroupConfigs().count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @"全部分组（左滑管理，右滑编辑成员）"; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    NSDictionary *g = WGGroupConfigs()[path.row]; UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    c.textLabel.text = g[@"name"]; c.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ 个成员", [g[@"visible"] boolValue] ? @"显示" : @"隐藏", @([g[@"members"] count])];
    c.accessoryType = [g[@"visible"] boolValue] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone; return c;
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path {
    NSDictionary *g=WGGroupConfigs()[path.row]; if (![g[@"isCustom"] boolValue]) return nil;
    UIContextualAction *delete = [[UIContextualAction alloc] initWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(__unused UIContextualAction *a, __unused UIView *v, void (^done)(BOOL)) { WGDeleteCustomGroup(g[@"name"]); [tableView reloadData]; done(YES); }];
    return [UISwipeActionsConfiguration configurationWithActions:@[delete]];
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path {
    NSDictionary *g=WGGroupConfigs()[path.row]; if (![g[@"isCustom"] boolValue]) return nil;
    UIContextualAction *edit = [[UIContextualAction alloc] initWithStyle:UIContextualActionStyleNormal title:@"成员" handler:^(__unused UIContextualAction *a, __unused UIView *v, void (^done)(BOOL)) { [self editMembers:g]; done(YES); }];
    return [UISwipeActionsConfiguration configurationWithActions:@[edit]];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path { NSDictionary*g=WGGroupConfigs()[path.row]; WGSetGroupVisible(g[@"name"], ![g[@"visible"] boolValue]); [tableView reloadData]; }
- (void)addGroup { UIAlertController *a=[UIAlertController alertControllerWithTitle:@"新增自定义分组" message:@"输入分组名称；创建后可左滑编辑成员微信号" preferredStyle:UIAlertControllerStyleAlert]; [a addTextFieldWithConfigurationHandler:^(UITextField*t){t.placeholder=@"例如：工作群";}]; [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [a addAction:[UIAlertAction actionWithTitle:@"创建" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction*x){ NSString*n=a.textFields.firstObject.text; if(!WGCreateCustomGroup(n,@[])){ UIAlertController*e=[UIAlertController alertControllerWithTitle:@"创建失败" message:@"名称为空或已存在" preferredStyle:UIAlertControllerStyleAlert]; [e addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:e animated:YES completion:nil]; } [self.tableView reloadData]; }]]; [self presentViewController:a animated:YES completion:nil]; }
- (void)editMembers:(NSDictionary *)g { UIAlertController*a=[UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@ · 成员",g[@"name"]] message:@"输入微信号，使用逗号或空格分隔" preferredStyle:UIAlertControllerStyleAlert]; [a addTextFieldWithConfigurationHandler:^(UITextField*t){t.text=[g[@"members"] componentsJoinedByString:@","]; t.placeholder=@"wxid_xxx,@chatroom";}]; [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction*x){ NSString*s=a.textFields.firstObject.text?:@""; NSCharacterSet*sep=[NSCharacterSet characterSetWithCharactersInString:@",， \n"]; NSMutableArray*m=[NSMutableArray array]; for(NSString*v in [s componentsSeparatedByCharactersInSet:sep])if(v.length)[m addObject:v]; WGSetGroupMembers(g[@"name"],m); [self.tableView reloadData]; }]]; [self presentViewController:a animated:YES completion:nil]; }
@end

@implementation WGSettingsController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"分组设置";
    self.tableView.estimatedRowHeight = 60;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }
- (void)dismissSettings { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    const NSInteger counts[] = {2, 1, 4, 1};
    return section >= 0 && section < 4 ? counts[section] : 0;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"分组", @"分类规则", @"运行状态与诊断", @"关于"][section];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"关闭后回到全部会话。设置入口始终保留，改动返回首页生效。";
    if (section == 1) return @"开启后，“好友”中排除文件传输助手等已知系统账号。好友仍按用户名规则识别，可能包含陌生人。";
    if (section == 2) return @"重试只重新检查接口和挂载，不移除签名保护。诊断不包含聊天内容、用户名或设备标识。调试日志仅记录接口与布局状态。";
    return @"独立纯分组测试版；不包含玻璃或调光功能。";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    NSString *key;
    if (path.section == 0 && path.row == 0) { cell.textLabel.text = @"启用分组"; key = kEnabled; }
    else if (path.section == 0 && path.row == 1) { cell.textLabel.text = @"管理分组"; cell.detailTextLabel.text = @"新增、隐藏、排序、重命名和编辑成员"; cell.textLabel.textColor = UIColor.systemBlueColor; cell.selectionStyle = UITableViewCellSelectionStyleDefault; }
    else if (path.section == 1) { cell.textLabel.text = @"好友中排除系统会话"; key = kExcludeSystem; }
    else if (path.section == 2 && path.row == 3) { cell.textLabel.text = @"调试日志"; key = kDebug; }
    else if (path.section == 2 && path.row == 0) {
        cell.textLabel.text = @"当前运行状态";
        cell.detailTextLabel.text = WGDiagnostics();
    } else if (path.section == 2) {
        cell.textLabel.text = path.row == 1 ? @"重新检测与挂载" : @"复制诊断信息";
        cell.textLabel.textColor = UIColor.systemBlueColor;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else {
        cell.textLabel.text = @"WeChatGroupExtractor";
        cell.detailTextLabel.text = @"0.0.3 · roothide arm64e\n首次使用先验证会话显示与点击对象一致。";
    }
    if (key) {
        UISwitch *control = [UISwitch new];
        control.accessibilityIdentifier = key;
        control.on = WGReadBool(key, ![key isEqualToString:kDebug]);
        [control addTarget:self action:@selector(change:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = control;
    }
    return cell;
}
- (void)change:(UISwitch *)control {
    NSString *key = control.accessibilityIdentifier;
    if (![@[kEnabled, kExcludeSystem, kDebug] containsObject:key]) return;
    WGWriteBool(key, control.on);
    [self.tableView reloadData];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section == 0 && path.row == 1) {
        [self.navigationController pushViewController:[WGGroupManagerController new] animated:YES];
        return;
    }
    if (path.section != 2) return;
    if (path.row == 1) {
        [NSNotificationCenter.defaultCenter postNotificationName:WGRequestRetry object:nil];
        [self.tableView reloadData];
    } else if (path.row == 2) {
        UIPasteboard.generalPasteboard.string = WGDiagnostics();
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已复制诊断信息"
            message:@"可以返回聊天粘贴反馈；不包含会话用户名或聊天内容。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}
@end
