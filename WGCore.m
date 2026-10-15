#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "WGSettings.h"
#import "WGABI.h"
#include <limits.h>
#include <string.h>

// Private APIs are checked on the installed WeChat version before enabling UI.
// A structurally valid build still requires device interaction testing.
typedef NS_ENUM(NSUInteger, WGFilter) { WGAll, WGFriends, WGGroups, WGOfficial };
static char kWGState;
static __thread unsigned int gNativeDepth;
static BOOL gReady;
static BOOL gWideCount;
static BOOL gWideCountSection;
static id (*gInfo)(id, SEL, id);
static id (*gBase)(id, SEL, id);
static id (*gCell)(id, SEL, id);
static unsigned int (*gCount32)(id, SEL, unsigned int);
static NSUInteger (*gCount64)(id, SEL, NSUInteger);
static NSUInteger (*gCount64Section32)(id, SEL, unsigned int);
static unsigned int (*gCount32Section64)(id, SEL, NSUInteger);
static id (*gReverse32)(id, SEL, id, unsigned int);
static id (*gReverse64)(id, SEL, id, NSUInteger);
static id (*gReversePath)(id, SEL, id);
static IMP gScalarReverse;
static BOOL gScalarReverseSectionWide;
static BOOL gScalarReverseSigned;
static void (*gDidAppear)(id, SEL, BOOL);
static void (*gDidLoad)(id, SEL);
static void (*gSettingsAppear)(id, SEL, BOOL);
static BOOL gInstallAttempted;
static BOOL gSettingsHooked;
static BOOL gHomeHooked;
static NSHashTable *gStates;
static SEL sCount, sInfo, sBase, sCell, sReverse;
static void WGInstall(void);
static void WGRefreshVisibleControllers(void);

static const char *WGUnqualified(const char *type) { return WGTypeUnqualified(type); }

static NSMethodSignature *WGSignature(Class cls, SEL selector) {
    Method method = class_getInstanceMethod(cls, selector);
    const char *types = method ? method_getTypeEncoding(method) : NULL;
    if (!types) return nil;
    @try { return [NSMethodSignature signatureWithObjCTypes:types]; }
    @catch (__unused NSException *exception) { return nil; }
}

static BOOL WGObjectMethod(Class cls, SEL selector, NSUInteger arguments) {
    NSMethodSignature *signature = WGSignature(cls, selector);
    if (!signature || signature.numberOfArguments != arguments + 2 ||
        *WGUnqualified(signature.methodReturnType) != '@') return NO;
    for (NSUInteger n = 2; n < signature.numberOfArguments; ++n)
        if (*WGUnqualified([signature getArgumentTypeAtIndex:n]) != '@') return NO;
    return YES;
}

static id WGObjectIvar(id object, const char *name) {
    if (!object) return nil;
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    if (!ivar || *WGUnqualified(ivar_getTypeEncoding(ivar)) != '@') return nil;
    return object_getIvar(object, ivar);
}

static NSString *WGUserName(id session) {
    if (!session) return nil;
    const char *names[] = {"m_nsUserName", "m_nsUsrName", "userName"};
    for (NSUInteger n = 0; n < 3; ++n) {
        SEL selector = sel_registerName(names[n]);
        if (WGObjectMethod(object_getClass(session), selector, 0)) {
            @try {
                id value = ((id (*)(id, SEL))[session methodForSelector:selector])(session, selector);
                if ([value isKindOfClass:NSString.class] && [value length]) return value;
            } @catch (__unused NSException *exception) { return nil; }
        }
        id value = WGObjectIvar(session, names[n]);
        if ([value isKindOfClass:NSString.class] && [value length]) return value;
    }
    return nil;
}

static BOOL WGMatches(NSString *user, WGFilter filter) {
    if (filter == WGAll) return YES;
    BOOL group = [user hasSuffix:@"@chatroom"];
    BOOL official = [user hasPrefix:@"gh_"] || [user isEqualToString:@"brandsessionholder"];
    if (filter == WGGroups) return group;
    if (filter == WGOfficial) return official;
    // Username heuristic, NOT proof of contact friendship. Exclude known holders/system IDs.
    static NSSet<NSString *> *systemUsers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        systemUsers = [NSSet setWithArray:@[@"newsapp", @"weixin", @"filehelper",
            @"notification_messages", @"fmessage", @"medianote", @"floatbottle",
            @"qmessage", @"tmessage", @"qqmail", @"masssendapp", @"feedsapp",
            @"shakeapp", @"voipapp", @"readerapp", @"linkedinplugin"]];
    });
    return user.length && !group && !official &&
        (!WGExcludeSystemUsers() || ![systemUsers containsObject:user]) &&
        [user rangeOfString:@"@"].location == NSNotFound;
}

@interface WGSnapshot : NSObject
@property(nonatomic) NSUInteger rawCount;
@property(nonatomic, copy) NSArray<NSNumber *> *rows;
@property(nonatomic, copy) NSArray<NSString *> *names;
@property(nonatomic) BOOL passthrough;
@end
@implementation WGSnapshot
@end

@interface WGState : NSObject
@property(nonatomic) WGFilter filter;
@property(nonatomic, weak) id logic;
@property(nonatomic, weak) UITableView *table;
@property(nonatomic, strong) UIView *banner;
@property(nonatomic, strong) UIView *bar;
@property(nonatomic, weak) UIViewController *controller;
@property(nonatomic, strong) UIView *previousTitleView;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, WGSnapshot *> *sections;
@property(nonatomic) BOOL reloadQueued;
@property(nonatomic) BOOL mountAttempted;
@property(nonatomic) BOOL fallbackMounted;
- (void)queueReload;
- (void)selectFilter:(WGFilter)filter;
@end

@implementation WGState
- (instancetype)init {
    if ((self = [super init])) _sections = [NSMutableDictionary dictionary];
    return self;
}
- (void)queueReload {
    if (self.reloadQueued) return;
    self.reloadQueued = YES;
    __weak WGState *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        WGState *state = weakSelf;
        if (!state) return;
        state.reloadQueued = NO;
        [state.sections removeAllObjects];
        // Never clear or replace WeChat's session/cell objects or its caches.
        if (state.table.window) [state.table reloadData];
    });
}
- (void)selectFilter:(WGFilter)filter {
    if (!WGEnabled() || filter > WGOfficial || self.filter == filter) return;
    self.filter = filter;
    [self.sections removeAllObjects];
    [self.table reloadData];
}
@end

static WGState *WGActiveState(id logic) {
    if (!gReady || !WGEnabled() || gNativeDepth || !NSThread.isMainThread) return nil;
    WGState *state = objc_getAssociatedObject(logic, &kWGState);
    return state.filter == WGAll ? nil : state;
}

static NSUInteger WGRawCount(id logic, NSUInteger section) {
    ++gNativeDepth;
    @try {
        if (gWideCount) {
            if (gWideCountSection) return gCount64(logic, sCount, section);
            return gCount64Section32(logic, sCount, (unsigned int)section);
        }
        if (gWideCountSection) return gCount32Section64(logic, sCount, section);
        return gCount32(logic, sCount, (unsigned int)section);
    } @finally { --gNativeDepth; }
}

static id WGRawObject(id (*original)(id, SEL, id), id logic, SEL selector, id indexPath) {
    ++gNativeDepth;
    @try { return original(logic, selector, indexPath); }
    @finally { --gNativeDepth; }
}

static WGSnapshot *WGBuildSnapshot(id logic, NSUInteger section, NSUInteger rawCount, WGState *state) {
    WGSnapshot *snapshot = [WGSnapshot new];
    snapshot.rawCount = rawCount;
    NSMutableArray<NSNumber *> *rows = [NSMutableArray array];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    // Limit main-thread scanning; unsupported/very large sections stay native.
    if (rawCount > 20000 || section > NSIntegerMax) snapshot.passthrough = YES;
    for (NSUInteger row = 0; row < rawCount && !snapshot.passthrough; ++row) {
        NSIndexPath *path = [NSIndexPath indexPathForRow:(NSInteger)row inSection:(NSInteger)section];
        NSString *user = WGUserName(WGRawObject(gInfo, logic, sInfo, path));
        if (!user) { snapshot.passthrough = YES; break; }
        if (WGMatches(user, state.filter)) { [rows addObject:@(row)]; [names addObject:user]; }
    }
    // Never publish a partial map if a private model could not be understood.
    snapshot.rows = snapshot.passthrough ? @[] : rows;
    snapshot.names = snapshot.passthrough ? @[] : names;
    state.sections[@(section)] = snapshot;
    return snapshot;
}

static NSUInteger WGFilteredCount(id logic, NSUInteger section) {
    NSUInteger raw = WGRawCount(logic, section);
    WGState *state = WGActiveState(logic);
    if (!state) return raw;
    WGSnapshot *snapshot = WGBuildSnapshot(logic, section, raw, state);
    return snapshot.passthrough ? raw : snapshot.rows.count;
}

static unsigned int WGCount32(id logic, SEL selector, unsigned int section) {
    return (unsigned int)WGFilteredCount(logic, section);
}
static NSUInteger WGCount64(id logic, SEL selector, NSUInteger section) {
    return WGFilteredCount(logic, section);
}
static NSUInteger WGCount64Section32(id logic, SEL selector, unsigned int section) {
    return WGFilteredCount(logic, section);
}
static unsigned int WGCount32Section64(id logic, SEL selector, NSUInteger section) {
    return (unsigned int)WGFilteredCount(logic, section);
}

// Returns a NATIVE index path. All three data getters use the same frozen map.
// Mapping is never applied recursively when WeChat getters call one another.
static NSIndexPath *WGNativePath(id logic, id input, WGState *state) {
    if (![input isKindOfClass:NSIndexPath.class] || [input length] != 2) return nil;
    NSIndexPath *path = input;
    if (path.section < 0 || path.row < 0) return nil;
    NSUInteger section = (NSUInteger)path.section;
    NSUInteger rawCount = WGRawCount(logic, section);
    WGSnapshot *snapshot = state.sections[@(section)];
    if (!snapshot) snapshot = WGBuildSnapshot(logic, section, rawCount, state);
    if (snapshot.passthrough) return (NSUInteger)path.row < rawCount ? path : nil;
    NSUInteger row = (NSUInteger)path.row;
    if (row >= snapshot.rows.count) { [state queueReload]; return nil; }
    NSUInteger rawRow = snapshot.rows[row].unsignedIntegerValue;
    NSString *expected = snapshot.names[row];
    if (rawRow < rawCount) {
        NSIndexPath *candidate = [NSIndexPath indexPathForRow:(NSInteger)rawRow inSection:path.section];
        NSString *actual = WGUserName(WGRawObject(gInfo, logic, sInfo, candidate));
        if ([actual isEqualToString:expected]) {
            if (snapshot.rawCount != rawCount) [state queueReload];
            return candidate;
        }
    }
    // A message may reorder a section without changing its count. Preserve the
    // requested session identity rather than using an unrelated native row.
    if (rawCount <= 20000) {
        for (NSUInteger n = 0; n < rawCount; ++n) {
            NSIndexPath *candidate = [NSIndexPath indexPathForRow:(NSInteger)n inSection:path.section];
            if ([WGUserName(WGRawObject(gInfo, logic, sInfo, candidate)) isEqualToString:expected]) {
                [state queueReload];
                return candidate;
            }
        }
    }
    [state queueReload];
    return nil; // Removed/invalid row: never silently open a different conversation.
}

static id WGGetObject(id (*original)(id, SEL, id), id logic, SEL selector, id input) {
    WGState *state = WGActiveState(logic);
    if (!state) return WGRawObject(original, logic, selector, input);
    NSIndexPath *native = WGNativePath(logic, input, state);
    return native ? WGRawObject(original, logic, selector, native) : nil;
}
static id WGInfo(id logic, SEL selector, id input) {
    return WGGetObject(gInfo, logic, selector, input);
}
static id WGBase(id logic, SEL selector, id input) {
    return WGGetObject(gBase, logic, selector, input);
}
static id WGCell(id logic, SEL selector, id input) {
    return WGGetObject(gCell, logic, selector, input);
}

static id WGReverse(id logic, SEL selector, id user, NSUInteger section, BOOL wide) {
    WGState *state = WGActiveState(logic);
    id native;
    ++gNativeDepth;
    @try {
        native = wide ? gReverse64(logic, selector, user, section) :
            gReverse32(logic, selector, user, (unsigned int)section);
    } @finally { --gNativeDepth; }
    if (!state || ![native isKindOfClass:NSIndexPath.class] || [native length] != 2)
        return state ? nil : native;
    NSIndexPath *path = native;
    if (path.section < 0 || path.row < 0) return nil;
    WGSnapshot *snapshot = state.sections[@(path.section)];
    NSUInteger rawCount = WGRawCount(logic, (NSUInteger)path.section);
    if (!snapshot) snapshot = WGBuildSnapshot(logic, (NSUInteger)path.section, rawCount, state);
    if (snapshot.passthrough) return native;
    // Invert using the SAME snapshot identities, not a second filtered getter.
    NSUInteger position = [snapshot.names indexOfObject:user];
    if (position == NSNotFound) return nil;
    if (snapshot.rawCount != rawCount || snapshot.rows[position].unsignedIntegerValue != (NSUInteger)path.row)
        [state queueReload];
    return [NSIndexPath indexPathForRow:(NSInteger)position inSection:path.section];
}
static id WGReverse32(id logic, SEL selector, id user, unsigned int section) {
    return WGReverse(logic, selector, user, section, NO);
}
static id WGReverse64(id logic, SEL selector, id user, NSUInteger section) {
    return WGReverse(logic, selector, user, section, YES);
}

// WeChatX's replacement at VA 0x38ea98 returns an integer row and uses
// 0x7fffffffffffffff for not-found. Do not require this method to return '@'.
static NSUInteger WGReverseRow(id logic, SEL selector, id user, NSUInteger section) {
    NSUInteger raw;
    ++gNativeDepth;
    @try {
        raw = gScalarReverseSectionWide ?
            ((NSUInteger (*)(id, SEL, id, NSUInteger))gScalarReverse)(logic, selector, user, section) :
            ((NSUInteger (*)(id, SEL, id, unsigned int))gScalarReverse)(logic, selector, user, (unsigned int)section);
    } @finally { --gNativeDepth; }
    WGState *state = WGActiveState(logic);
    if (!state) return raw;
    NSUInteger rawCount = WGRawCount(logic, section);
    WGSnapshot *snapshot = state.sections[@(section)];
    if (!snapshot) snapshot = WGBuildSnapshot(logic, section, rawCount, state);
    if (snapshot.passthrough) return raw;
    // Keep the native not-found sentinel unchanged when it was returned.
    if (raw >= rawCount) return raw;
    NSUInteger position = [snapshot.names indexOfObject:user];
    if (position == NSNotFound) return gScalarReverseSigned ? (NSUInteger)NSIntegerMax : NSNotFound;
    if (snapshot.rawCount != rawCount || snapshot.rows[position].unsignedIntegerValue != raw)
        [state queueReload];
    return position;
}
static NSUInteger WGReverseRowSection32(id logic, SEL selector, id user, unsigned int section) {
    return WGReverseRow(logic, selector, user, section);
}

static id WGReversePath(id logic, SEL selector, id user) {
    id native;
    ++gNativeDepth;
    @try { native = gReversePath(logic, selector, user); }
    @finally { --gNativeDepth; }
    WGState *state = WGActiveState(logic);
    if (!state) return native;
    if (![native isKindOfClass:NSIndexPath.class] || [native length] != 2) return nil;
    NSIndexPath *path = native;
    if (path.section < 0 || path.row < 0) return nil;
    NSUInteger rawCount = WGRawCount(logic, (NSUInteger)path.section);
    WGSnapshot *snapshot = state.sections[@(path.section)];
    if (!snapshot) snapshot = WGBuildSnapshot(logic, (NSUInteger)path.section, rawCount, state);
    if (snapshot.passthrough) return native;
    NSUInteger position = [snapshot.names indexOfObject:user];
    return position == NSNotFound ? nil : [NSIndexPath indexPathForRow:(NSInteger)position inSection:path.section];
}

// Plain controls; the trailing settings button remains reachable when filtering is off.
@interface WGSegmentBar : UIView
@property(nonatomic, weak) WGState *state;
@property(nonatomic, strong) NSArray<UIButton *> *buttons;
@property(nonatomic, strong) UIButton *settingsButton;
- (void)refresh;
@end
@implementation WGSegmentBar
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        NSArray<NSString *> *titles = @[@"全部", @"好友", @"群聊", @"订阅号"];
        NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
        for (NSUInteger n = 0; n < titles.count; ++n) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            button.tag = (NSInteger)n;
            [button setTitle:titles[n] forState:UIControlStateNormal];
            button.titleLabel.font = [UIFont systemFontOfSize:15];
            [button addTarget:self action:@selector(select:) forControlEvents:UIControlEventTouchUpInside];
            [self addSubview:button];
            [buttons addObject:button];
        }
        self.buttons = buttons;
        self.settingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.settingsButton setTitle:@"设置" forState:UIControlStateNormal];
        self.settingsButton.titleLabel.font = [UIFont systemFontOfSize:13];
        [self.settingsButton addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.settingsButton];
        self.backgroundColor = UIColor.systemBackgroundColor;
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat settingsWidth = 44;
    CGFloat width = MAX(0, self.bounds.size.width - settingsWidth) / 4.0;
    for (NSUInteger n = 0; n < self.buttons.count; ++n)
        self.buttons[n].frame = CGRectMake(n * width, 0, width, self.bounds.size.height);
    self.settingsButton.frame = CGRectMake(width * 4, 0, settingsWidth, self.bounds.size.height);
}
- (CGSize)intrinsicContentSize { return CGSizeMake(300, 40); }
- (void)openSettings { WGPresentSettings(self.state.controller); }
- (void)select:(UIButton *)button {
    [self.state selectFilter:(WGFilter)button.tag];
    [self refresh];
}
- (void)refresh {
    for (UIButton *button in self.buttons) {
        button.enabled = WGEnabled() && gReady && self.state.logic && self.state.table;
        BOOL active = (NSUInteger)button.tag == self.state.filter && button.enabled;
        [button setTitleColor:active ? UIColor.systemBlueColor : UIColor.labelColor forState:UIControlStateNormal];
        button.titleLabel.font = active ? [UIFont boldSystemFontOfSize:15] : [UIFont systemFontOfSize:15];
        button.accessibilityTraits = UIAccessibilityTraitButton | (active ? UIAccessibilityTraitSelected : 0);
    }
}
@end

static BOOL WGHeaderCanMount(id header, SEL selector) {
    NSMethodSignature *signature = WGSignature(object_getClass(header), selector);
    if (!signature || signature.numberOfArguments != 5 ||
        strcmp(WGUnqualified(signature.methodReturnType), "v") ||
        *WGUnqualified([signature getArgumentTypeAtIndex:2]) != '@') return NO;
    const char *indexType = WGUnqualified([signature getArgumentTypeAtIndex:3]);
    const char *boolType = WGUnqualified([signature getArgumentTypeAtIndex:4]);
    return (!strcmp(indexType, "I") || !strcmp(indexType, "Q")) &&
        (!strcmp(boolType, "B") || !strcmp(boolType, "c"));
}

static id WGFindDirectObject(id owner, Class expected) {
    if (!owner || !expected) return nil;
    // Only inspect direct object ivars, with a known expected class; no private KVC.
    for (Class cls = object_getClass(owner); cls && cls != UIViewController.class; cls = class_getSuperclass(cls)) {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(cls, &count);
        id found = nil;
        for (unsigned int n = 0; n < count; ++n) {
            if (*WGUnqualified(ivar_getTypeEncoding(ivars[n])) != '@') continue;
            id value = object_getIvar(owner, ivars[n]);
            if ([value isKindOfClass:expected]) { found = value; break; }
        }
        free(ivars);
        if (found) return found;
    }
    return nil;
}

static UITableView *WGFindTable(UIViewController *controller) {
    id table = WGObjectIvar(controller, "m_tableView");
    if ([table isKindOfClass:UITableView.class]) return table;
    table = WGFindDirectObject(controller, UITableView.class);
    if (table) return table;
    if (!controller.isViewLoaded) return nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:controller.view];
    for (NSUInteger n = 0; n < queue.count && n < 256; ++n) {
        UIView *view = queue[n];
        if ([view isKindOfClass:UITableView.class]) return (UITableView *)view;
        if (queue.count < 512) [queue addObjectsFromArray:view.subviews];
    }
    return nil;
}

static void WGFallback(WGState *state, NSString *reason) {
    UIViewController *controller = state.controller;
    if (!controller || !controller.navigationController) {
        WGRecordStatus(@"挂载", [reason stringByAppendingString:@"；等待导航容器"]);
        return;
    }
    WGSegmentBar *bar = (WGSegmentBar *)state.bar;
    [bar removeFromSuperview];
    if (!state.fallbackMounted) state.previousTitleView = controller.navigationItem.titleView;
    bar.frame = CGRectMake(0, 0, MIN(MAX(controller.view.bounds.size.width - 100, 250), 320), 40);
    bar.autoresizingMask = UIViewAutoresizingNone;
    controller.navigationItem.titleView = bar;
    state.fallbackMounted = YES;
    [bar refresh];
    WGRecordStatus(@"挂载", [reason stringByAppendingString:@"；已使用首页导航栏备用位置"]);
}

static void WGMount(id rawController) {
    if (!NSThread.isMainThread || ![rawController isKindOfClass:UIViewController.class]) return;
    UIViewController *controller = rawController;
    if (!controller.isViewLoaded) return;
    Class logicClass = objc_getClass("MainFrameLogicController");
    id logic = WGObjectIvar(controller, "m_mainFrameLogicController");
    if (![logic isKindOfClass:logicClass]) logic = WGFindDirectObject(controller, logicClass);
    id header = WGObjectIvar(controller, "m_headerLogic");
    if (!header) header = WGFindDirectObject(controller, objc_getClass("MainFrameHeaderLogic"));
    UITableView *table = WGFindTable(controller);
    WGState *state = objc_getAssociatedObject(controller, &kWGState);
    if (!state) {
        state = [WGState new];
        objc_setAssociatedObject(controller, &kWGState, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!gStates) gStates = [NSHashTable weakObjectsHashTable];
        [gStates addObject:state];
    }
    state.controller = controller;
    state.logic = logic;
    state.table = table;
    if (logic) objc_setAssociatedObject(logic, &kWGState, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!state.bar) {
        WGSegmentBar *bar = [[WGSegmentBar alloc] initWithFrame:CGRectMake(0, 0, 300, 46)];
        bar.state = state;
        state.bar = bar;
    }
    [(WGSegmentBar *)state.bar refresh];
    if (!logic || !table || !gReady) {
        WGFallback(state, !gReady ? @"核心接口未就绪，分类按钮已禁用" : @"未找到首页逻辑对象或会话表格，分类按钮已禁用");
        return;
    }
    if (state.bar.superview == state.banner && state.bar.window &&
        !state.banner.hidden && state.banner.bounds.size.height > 1) {
        WGRecordStatus(@"挂载", @"原生 MFBannerBtn 已在窗口内");
        return;
    }
    if (state.mountAttempted) {
        WGFallback(state, @"原生横幅未显示，不重复插入原生队列");
        return;
    }
    Class bannerClass = objc_getClass("MFBannerBtn");
    SEL add = sel_registerName("addBannerBtn:atIndex:withAnim:");
    if (!bannerClass || ![bannerClass isSubclassOfClass:UIView.class] || !WGHeaderCanMount(header, add) || table.bounds.size.width <= 0) {
        WGFallback(state, @"原生横幅接口或尺寸不可用");
        return;
    }
    @try {
        UIView *banner = [[bannerClass alloc] initWithFrame:CGRectMake(0, 0, table.bounds.size.width, 46)];
        if (![banner isKindOfClass:bannerClass]) { WGFallback(state, @"原生横幅初始化失败"); return; }
        WGSegmentBar *bar = (WGSegmentBar *)state.bar;
        if (state.fallbackMounted && controller.navigationItem.titleView == bar)
            controller.navigationItem.titleView = state.previousTitleView;
        state.fallbackMounted = NO;
        [bar removeFromSuperview];
        bar.frame = banner.bounds;
        bar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        banner.userInteractionEnabled = YES;
        [banner addSubview:bar];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:WGSignature(object_getClass(header), add)];
        NSUInteger index = 0;
        BOOL animate = NO;
        [invocation setTarget:header];
        [invocation setSelector:add];
        [invocation setArgument:&banner atIndex:2];
        [invocation setArgument:&index atIndex:3];
        [invocation setArgument:&animate atIndex:4];
        state.mountAttempted = YES; // A failed insertion may be partial; never repeat it.
        state.banner = banner;
        [invocation invoke];
        WGRecordStatus(@"挂载", @"已提交原生横幅队列，等待可见性检查");
        __weak WGState *weakState = state;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
            WGState *current = weakState;
            if (!current) return;
            if (current.bar.superview != current.banner || !current.bar.window ||
                current.banner.hidden || current.banner.bounds.size.height < 1)
                WGFallback(current, @"原生横幅插入后未显示");
            else WGRecordStatus(@"挂载", @"原生 MFBannerBtn 已在窗口内");
        });
    } @catch (__unused NSException *exception) {
        WGFallback(state, @"原生横幅接口发生异常");
    }
}

static void WGDidAppear(id controller, SEL selector, BOOL animated) {
    gDidAppear(controller, selector, animated);
    WGInstall();
    WGMount(controller);
}
static void WGDidLoad(id controller, SEL selector) {
    gDidLoad(controller, selector);
    WGInstall();
    __weak id weakController = controller;
    dispatch_async(dispatch_get_main_queue(), ^{ WGMount(weakController); });
}
static void WGSettingsAppear(id controller, SEL selector, BOOL animated) {
    gSettingsAppear(controller, selector, animated);
    WGAttachSettingsEntry(controller);
}

static BOOL WGLifecycle(Class cls, SEL selector, BOOL hasBool) {
    NSMethodSignature *signature = WGSignature(cls, selector);
    return signature && signature.numberOfArguments == (hasBool ? 3 : 2) &&
        !strcmp(WGUnqualified(signature.methodReturnType), "v") &&
        (!hasBool || WGIsBool([signature getArgumentTypeAtIndex:2]));
}

static void WGInstallUI(void) {
    Class settings = objc_getClass("NewSettingViewController");
    Class home = objc_getClass("NewMainFrameViewController");
    SEL appear = @selector(viewDidAppear:);
    if (!gSettingsHooked && settings && [settings isSubclassOfClass:UIViewController.class] && WGLifecycle(settings, appear, YES)) {
        MSHookMessageEx(settings, appear, (IMP)WGSettingsAppear, (IMP *)&gSettingsAppear);
        gSettingsHooked = gSettingsAppear != NULL;
        WGRecordStatus(@"设置入口", gSettingsHooked ? @"已安装独立设置页 hook，打开微信设置后添加右上角按钮" : @"设置页 hook 原函数不可用");
    }
    if (!gSettingsHooked) WGRecordStatus(@"设置入口", @"等待 NewSettingViewController 加载或版本不兼容");
    if (!gHomeHooked && home && [home isSubclassOfClass:UIViewController.class] && WGLifecycle(home, appear, YES)) {
        MSHookMessageEx(home, appear, (IMP)WGDidAppear, (IMP *)&gDidAppear);
        if (WGLifecycle(home, @selector(viewDidLoad), NO))
            MSHookMessageEx(home, @selector(viewDidLoad), (IMP)WGDidLoad, (IMP *)&gDidLoad);
        gHomeHooked = gDidAppear != NULL;
        WGRecordStatus(@"首页入口", gHomeHooked ? @"首页生命周期 hook 已安装" : @"首页 hook 原函数不可用");
    }
}

static NSString *WGEncoding(Class cls, SEL selector) {
    Method method = class_getInstanceMethod(cls, selector);
    const char *type = method ? method_getTypeEncoding(method) : NULL;
    return type ? [NSString stringWithUTF8String:type] : @"缺失";
}

static void WGInstall(void) {
    WGInstallUI(); // UI/diagnostics must NOT depend on filtering ABI compatibility.
    if (gReady || gInstallAttempted) return;
    Class logic = objc_getClass("MainFrameLogicController");
    sCount = sel_registerName("getSessionCountForSection:");
    sInfo = sel_registerName("getSessionInfoAtIndexPath:");
    sBase = sel_registerName("getSessionBaseInfoAtIndexPath:");
    sCell = sel_registerName("getCellDataAtIndexPath:");
    sReverse = sel_registerName("indexOfSessionUserName:inSection:");
    if (!logic) { WGRecordStatus(@"核心接口", @"等待 MainFrameLogicController 加载"); return; }
    WGRecordStatus(@"计数签名", WGEncoding(logic, sCount));
    WGRecordStatus(@"反向索引签名", WGEncoding(logic, sReverse));
    NSMethodSignature *count = WGSignature(logic, sCount);
    NSMethodSignature *reverse = WGSignature(logic, sReverse);
    if (!count || !reverse || count.numberOfArguments != 3 || reverse.numberOfArguments != 4 ||
        *WGUnqualified([reverse getArgumentTypeAtIndex:2]) != '@' ||
        !WGObjectMethod(logic, sInfo, 1) || !WGObjectMethod(logic, sBase, 1) || !WGObjectMethod(logic, sCell, 1)) {
        WGRecordStatus(@"核心接口", @"数据源接口缺失或 getter 参数不兼容；未开启过滤");
        return;
    }
    unsigned countResult = WGIntegerWidth(count.methodReturnType);
    unsigned countSection = WGIntegerWidth([count getArgumentTypeAtIndex:2]);
    unsigned reverseSection = WGIntegerWidth([reverse getArgumentTypeAtIndex:3]);
    BOOL objectReverse = *WGUnqualified(reverse.methodReturnType) == '@';
    BOOL scalarReverse = WGIntegerWidth(reverse.methodReturnType) == 8;
    if (!countResult || !countSection || !reverseSection || (!objectReverse && !scalarReverse)) {
        WGRecordStatus(@"核心接口", @"计数/反向索引 ABI 不支持；未开启过滤，请复制诊断");
        return;
    }
    SEL reversePath = sel_registerName("indexPathOfSessionUserName:");
    if (class_getInstanceMethod(logic, reversePath) && !WGObjectMethod(logic, reversePath, 1)) {
        WGRecordStatus(@"核心接口", @"indexPath 反向查找 ABI 不兼容；未开启过滤");
        return;
    }
    gWideCount = countResult == 8;
    gWideCountSection = countSection == 8;
    gInstallAttempted = YES; // Installation is not atomic; never double-hook a partial batch.
    MSHookMessageEx(logic, sInfo, (IMP)WGInfo, (IMP *)&gInfo);
    MSHookMessageEx(logic, sBase, (IMP)WGBase, (IMP *)&gBase);
    MSHookMessageEx(logic, sCell, (IMP)WGCell, (IMP *)&gCell);
    IMP countReplacement = gWideCount ? (gWideCountSection ? (IMP)WGCount64 : (IMP)WGCount64Section32) :
        (gWideCountSection ? (IMP)WGCount32Section64 : (IMP)WGCount32);
    if (gWideCount && gWideCountSection) MSHookMessageEx(logic, sCount, countReplacement, (IMP *)&gCount64);
    else if (gWideCount) MSHookMessageEx(logic, sCount, countReplacement, (IMP *)&gCount64Section32);
    else if (gWideCountSection) MSHookMessageEx(logic, sCount, countReplacement, (IMP *)&gCount32Section64);
    else MSHookMessageEx(logic, sCount, countReplacement, (IMP *)&gCount32);
    BOOL reverseOK;
    if (scalarReverse) {
        gScalarReverseSectionWide = reverseSection == 8;
        gScalarReverseSigned = strchr("ql", *WGUnqualified(reverse.methodReturnType)) != NULL;
        MSHookMessageEx(logic, sReverse, gScalarReverseSectionWide ? (IMP)WGReverseRow : (IMP)WGReverseRowSection32, &gScalarReverse);
        reverseOK = gScalarReverse != NULL;
    } else if (reverseSection == 8) {
        MSHookMessageEx(logic, sReverse, (IMP)WGReverse64, (IMP *)&gReverse64);
        reverseOK = gReverse64 != NULL;
    } else {
        MSHookMessageEx(logic, sReverse, (IMP)WGReverse32, (IMP *)&gReverse32);
        reverseOK = gReverse32 != NULL;
    }
    BOOL pathOK = YES;
    if (class_getInstanceMethod(logic, reversePath)) {
        MSHookMessageEx(logic, reversePath, (IMP)WGReversePath, (IMP *)&gReversePath);
        pathOK = gReversePath != NULL;
    }
    BOOL countOK = gWideCount ? (gWideCountSection ? gCount64 != NULL : gCount64Section32 != NULL) :
        (gWideCountSection ? gCount32Section64 != NULL : gCount32 != NULL);
    gReady = gInfo && gBase && gCell && countOK && reverseOK && pathOK;
    WGRecordStatus(@"核心接口", gReady ? @"数据源 hook 已就绪（仍需验证真实会话交互）" : @"安装未完整，未开启过滤；请关闭微信后重开");
}

static void WGVisitController(UIViewController *controller, NSUInteger depth) {
    if (!controller || depth > 12 || !controller.isViewLoaded) return;
    Class settings = objc_getClass("NewSettingViewController");
    Class home = objc_getClass("NewMainFrameViewController");
    if (settings && [controller isKindOfClass:settings]) WGAttachSettingsEntry(controller);
    if (home && [controller isKindOfClass:home]) WGMount(controller);
    for (UIViewController *child in controller.childViewControllers) WGVisitController(child, depth + 1);
    WGVisitController(controller.presentedViewController, depth + 1);
}
static void WGRefreshVisibleControllers(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows)
            if (!window.hidden && window.windowLevel == UIWindowLevelNormal) WGVisitController(window.rootViewController, 0);
    }
}

static void WGPreferencesDidChange(void) {
    for (WGState *state in gStates.allObjects) {
        if (!WGEnabled()) state.filter = WGAll;
        [state.sections removeAllObjects];
        [(WGSegmentBar *)state.bar refresh];
        [state queueReload];
    }
}

__attribute__((constructor)) static void WGInitialize(void) {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.tencent.xin"]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            WGRecordStatus(@"插件版本", @"0.0.3 已加载");
            [NSNotificationCenter.defaultCenter addObserverForName:WGPreferencesChanged object:nil queue:NSOperationQueue.mainQueue
                usingBlock:^(__unused NSNotification *note) { WGPreferencesDidChange(); }];
            for (NSString *name in @[WGRequestRetry, UIApplicationDidBecomeActiveNotification])
                [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification *note) { WGInstall(); WGRefreshVisibleControllers(); }];
            // Retry unloaded classes and catch pages whose first appearance preceded injection.
            const int seconds[] = {0, 1, 3, 8, 15, 30};
            for (NSUInteger n = 0; n < sizeof(seconds) / sizeof(seconds[0]); ++n)
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)seconds[n] * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    WGInstall(); WGRefreshVisibleControllers();
                });
        });
    }
}
