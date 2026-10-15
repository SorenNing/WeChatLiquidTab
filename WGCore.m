#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#include <limits.h>
#include <string.h>

// Private APIs are checked on the installed WeChat version before enabling UI.
// A structurally valid build still requires device interaction testing.
typedef NS_ENUM(NSUInteger, WGFilter) { WGAll, WGFriends, WGGroups, WGOfficial };
static char kWGState;
static __thread unsigned int gNativeDepth;
static BOOL gReady;
static BOOL gWideCount;
static id (*gInfo)(id, SEL, id);
static id (*gBase)(id, SEL, id);
static id (*gCell)(id, SEL, id);
static unsigned int (*gCount32)(id, SEL, unsigned int);
static NSUInteger (*gCount64)(id, SEL, NSUInteger);
static id (*gReverse32)(id, SEL, id, unsigned int);
static id (*gReverse64)(id, SEL, id, NSUInteger);
static void (*gDidAppear)(id, SEL, BOOL);
static SEL sCount, sInfo, sBase, sCell, sReverse;

static const char *WGUnqualified(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) ++type;
    return type ?: "";
}

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
    return user.length && !group && !official && ![systemUsers containsObject:user] &&
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
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, WGSnapshot *> *sections;
@property(nonatomic) BOOL reloadQueued;
@property(nonatomic) BOOL mountAttempted;
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
    if (filter > WGOfficial || self.filter == filter) return;
    self.filter = filter;
    [self.sections removeAllObjects];
    [self.table reloadData];
}
@end

static WGState *WGActiveState(id logic) {
    if (!gReady || gNativeDepth || !NSThread.isMainThread) return nil;
    WGState *state = objc_getAssociatedObject(logic, &kWGState);
    return state.filter == WGAll ? nil : state;
}

static NSUInteger WGRawCount(id logic, NSUInteger section) {
    ++gNativeDepth;
    @try {
        return gWideCount ? gCount64(logic, sCount, section) :
            gCount32(logic, sCount, (unsigned int)section);
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

// Plain controls: no effect view, glass shader, custom blur, shadows or settings UI.
@interface WGSegmentBar : UIView
@property(nonatomic, weak) WGState *state;
@property(nonatomic, strong) NSArray<UIButton *> *buttons;
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
        self.backgroundColor = UIColor.systemBackgroundColor;
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = MAX(0, self.bounds.size.width) / 4.0;
    for (NSUInteger n = 0; n < self.buttons.count; ++n)
        self.buttons[n].frame = CGRectMake(n * width, 0, width, self.bounds.size.height);
}
- (void)select:(UIButton *)button {
    [self.state selectFilter:(WGFilter)button.tag];
    [self refresh];
}
- (void)refresh {
    for (UIButton *button in self.buttons) {
        BOOL active = (NSUInteger)button.tag == self.state.filter;
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

static void WGMount(id controller) {
    if (!gReady || !NSThread.isMainThread) return;
    id logic = WGObjectIvar(controller, "m_mainFrameLogicController");
    id header = WGObjectIvar(controller, "m_headerLogic");
    id rawTable = WGObjectIvar(controller, "m_tableView");
    Class logicClass = objc_getClass("MainFrameLogicController");
    Class bannerClass = objc_getClass("MFBannerBtn");
    SEL add = sel_registerName("addBannerBtn:atIndex:withAnim:");
    if (!logic || ![logic isKindOfClass:logicClass] || ![rawTable isKindOfClass:UITableView.class] ||
        !bannerClass || ![bannerClass isSubclassOfClass:UIView.class] || !WGHeaderCanMount(header, add)) return;
    UITableView *table = rawTable;
    WGState *state = objc_getAssociatedObject(controller, &kWGState);
    if (!state) {
        state = [WGState new];
        objc_setAssociatedObject(controller, &kWGState, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    state.logic = logic;
    state.table = table;
    objc_setAssociatedObject(logic, &kWGState, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (state.mountAttempted) return;
    state.mountAttempted = YES; // Do not retry a possibly partial native queue insertion.
    CGFloat width = table.bounds.size.width;
    if (width <= 0) { state.mountAttempted = NO; return; }
    @try {
        UIView *banner = [[bannerClass alloc] initWithFrame:CGRectMake(0, 0, width, 46)];
        if (![banner isKindOfClass:bannerClass]) return;
        WGSegmentBar *bar = [[WGSegmentBar alloc] initWithFrame:banner.bounds];
        bar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        bar.state = state;
        [bar refresh];
        banner.userInteractionEnabled = YES;
        [banner addSubview:bar];
        // NSInvocation supplies correctly sized zero-valued int/BOOL arguments.
        NSMethodSignature *signature = WGSignature(object_getClass(header), add);
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        NSUInteger index = 0;
        BOOL animate = NO;
        [invocation setTarget:header];
        [invocation setSelector:add];
        [invocation setArgument:&banner atIndex:2];
        [invocation setArgument:&index atIndex:3];
        [invocation setArgument:&animate atIndex:4];
        [invocation invoke];
        state.banner = banner;
    } @catch (__unused NSException *exception) {
        state.filter = WGAll;
        [state.sections removeAllObjects];
        NSLog(@"[WeChatGroupExtractor] Native banner unavailable; filtering disabled.");
    }
}

static void WGDidAppear(id controller, SEL selector, BOOL animated) {
    gDidAppear(controller, selector, animated);
    WGMount(controller);
}

static void WGInstall(void) {
    Class logic = objc_getClass("MainFrameLogicController");
    Class controller = objc_getClass("NewMainFrameViewController");
    sCount = sel_registerName("getSessionCountForSection:");
    sInfo = sel_registerName("getSessionInfoAtIndexPath:");
    sBase = sel_registerName("getSessionBaseInfoAtIndexPath:");
    sCell = sel_registerName("getCellDataAtIndexPath:");
    sReverse = sel_registerName("indexOfSessionUserName:inSection:");
    SEL appear = @selector(viewDidAppear:);
    NSMethodSignature *count = WGSignature(logic, sCount);
    NSMethodSignature *reverse = WGSignature(logic, sReverse);
    NSMethodSignature *life = WGSignature(controller, appear);
    if (!logic || !controller || !count || !reverse || !life ||
        count.numberOfArguments != 3 || reverse.numberOfArguments != 4 ||
        life.numberOfArguments != 3 ||
        strcmp(WGUnqualified(life.methodReturnType), "v") ||
        !strchr("Bc", *WGUnqualified([life getArgumentTypeAtIndex:2])) ||
        *WGUnqualified(reverse.methodReturnType) != '@' ||
        *WGUnqualified([reverse getArgumentTypeAtIndex:2]) != '@' ||
        !WGObjectMethod(logic, sInfo, 1) || !WGObjectMethod(logic, sBase, 1) ||
        !WGObjectMethod(logic, sCell, 1)) {
        NSLog(@"[WeChatGroupExtractor] Unsupported private API; hooks not installed.");
        return;
    }
    const char *returnType = WGUnqualified(count.methodReturnType);
    const char *sectionType = WGUnqualified([count getArgumentTypeAtIndex:2]);
    const char *reverseSection = WGUnqualified([reverse getArgumentTypeAtIndex:3]);
    BOOL count32 = !strcmp(returnType, "I") && !strcmp(sectionType, "I");
    BOOL count64 = !strcmp(returnType, "Q") && !strcmp(sectionType, "Q");
    BOOL reverse32 = !strcmp(reverseSection, "I");
    BOOL reverse64 = !strcmp(reverseSection, "Q");
    if ((!count32 && !count64) || (!reverse32 && !reverse64)) {
        NSLog(@"[WeChatGroupExtractor] Unknown count/index ABI; hooks not installed.");
        return;
    }
    gWideCount = count64;
    MSHookMessageEx(logic, sInfo, (IMP)WGInfo, (IMP *)&gInfo);
    MSHookMessageEx(logic, sBase, (IMP)WGBase, (IMP *)&gBase);
    MSHookMessageEx(logic, sCell, (IMP)WGCell, (IMP *)&gCell);
    if (count64) MSHookMessageEx(logic, sCount, (IMP)WGCount64, (IMP *)&gCount64);
    else MSHookMessageEx(logic, sCount, (IMP)WGCount32, (IMP *)&gCount32);
    if (reverse64) MSHookMessageEx(logic, sReverse, (IMP)WGReverse64, (IMP *)&gReverse64);
    else MSHookMessageEx(logic, sReverse, (IMP)WGReverse32, (IMP *)&gReverse32);
    gReady = gInfo && gBase && gCell && (count64 ? (BOOL)(gCount64 != NULL) : (BOOL)(gCount32 != NULL)) &&
        (reverse64 ? (BOOL)(gReverse64 != NULL) : (BOOL)(gReverse32 != NULL));
    if (gReady) MSHookMessageEx(controller, appear, (IMP)WGDidAppear, (IMP *)&gDidAppear);
}

__attribute__((constructor)) static void WGInitialize(void) {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.tencent.xin"]) return;
        dispatch_async(dispatch_get_main_queue(), ^{ WGInstall(); });
    }
}
