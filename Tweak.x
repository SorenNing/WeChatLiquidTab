#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "SettingViewController.h"

// ====================================================================
// 微信核心类与接口声明
// ====================================================================
@interface MMSessionInfo : NSObject
@property (nonatomic, strong) NSString *m_nsUserName;
@property (nonatomic, assign) unsigned int m_uiUnReadCnt;
@end

@interface MMNewSessionMgr : NSObject
- (id)GetAllSession;
- (id)GetSessionInfo:(id)arg1;
@end

@interface MMServiceCenter : NSObject
+ (id)defaultCenter;
- (id)getService:(Class)cls;
@end

@interface MainFrameLogicController : NSObject
- (unsigned int)getSessionCountForSection:(unsigned int)section;
- (id)getSessionInfoAtIndexPath:(id)indexPath;
- (id)getCellDataAtIndexPath:(id)indexPath;
- (id)indexOfSessionUserName:(id)userName inSection:(unsigned int)section;
@end

@interface MainFrameHeaderLogic : NSObject
- (void)addBannerBtn:(id)arg1 withAnim:(_Bool)arg2;
- (void)addBannerBtn:(id)arg1 atIndex:(unsigned int)arg2 withAnim:(_Bool)arg3;
@end

@interface NewMainFrameViewController : UIViewController
{
    MainFrameHeaderLogic *m_headerLogic;
    MainFrameLogicController *m_mainFrameLogicController;
    UITableView *m_tableView;
}
@end

@interface MFBannerBtn : UIButton
@end

// ====================================================================
// 配置项宏与存取
// ====================================================================
#define UD [NSUserDefaults standardUserDefaults]
#define K_ENABLED @"WCLiquid_enabled"
#define K_LIVE_BLUR @"WCLiquid_enableLiveBlur"
#define K_BLUR_INTENSITY @"WCLiquid_blurIntensity"
#define K_SPECULAR @"WCLiquid_enableSpecular"
#define K_SPECULAR_INTENSITY @"WCLiquid_specularIntensity"
#define K_RIM_LIGHT @"WCLiquid_enableRimLight"
#define K_RIM_WIDTH @"WCLiquid_rimBorderWidth"
#define K_GESTURE @"WCLiquid_enableSwipeGesture"

static BOOL getPrefBool(NSString *key, BOOL defaultVal) {
    return [UD objectForKey:key] ? [UD boolForKey:key] : defaultVal;
}

static CGFloat getPrefFloat(NSString *key, CGFloat defaultVal) {
    return [UD objectForKey:key] ? [UD floatForKey:key] : defaultVal;
}

static UIColor *getDynamicGlassTint(CGFloat intensity) {
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            if (traits.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor colorWithWhite:1.0 alpha:(intensity * 0.25)];
            } else {
                return [UIColor colorWithWhite:1.0 alpha:(intensity * 0.75)];
            }
        }];
    }
    return [UIColor colorWithWhite:1.0 alpha:0.25];
}

static UIColor *getDynamicRimBorderColor(void) {
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            if (traits.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor colorWithWhite:1.0 alpha:0.35];
            } else {
                return [UIColor colorWithWhite:1.0 alpha:0.75];
            }
        }];
    }
    return [UIColor colorWithWhite:1.0 alpha:0.75];
}

// ====================================================================
// 分组类型与会话数据源管理
// ====================================================================
typedef NS_ENUM(NSInteger, WCLiquidFilterType) {
    WCLiquidFilterTypeAll = 0,
    WCLiquidFilterTypeFriends,
    WCLiquidFilterTypeGroups,
    WCLiquidFilterTypeOfficial
};

static WCLiquidFilterType gActiveFilter = WCLiquidFilterTypeAll;
static NSMutableArray<MMSessionInfo *> *gFilteredSessions = nil;

static void updateFilteredSessions(void) {
    if (!gFilteredSessions) {
        gFilteredSessions = [NSMutableArray array];
    }
    [gFilteredSessions removeAllObjects];

    MMNewSessionMgr *mgr = [[%c(MMServiceCenter) defaultCenter] getService:%c(MMNewSessionMgr)];
    if (!mgr) return;

    NSArray *all = [mgr GetAllSession];
    for (MMSessionInfo *info in all) {
        NSString *u = info.m_nsUserName;
        if (!u) continue;

        if (gActiveFilter == WCLiquidFilterTypeGroups) {
            if ([u hasSuffix:@"@chatroom"]) {
                [gFilteredSessions addObject:info];
            }
        } else if (gActiveFilter == WCLiquidFilterTypeOfficial) {
            if ([u hasPrefix:@"gh_"]) {
                [gFilteredSessions addObject:info];
            }
        } else if (gActiveFilter == WCLiquidFilterTypeFriends) {
            if (![u hasSuffix:@"@chatroom"] && ![u hasPrefix:@"gh_"]) {
                [gFilteredSessions addObject:info];
            }
        } else {
            [gFilteredSessions addObject:info];
        }
    }
}

// ====================================================================
// 苹果连续曲率液态玻璃胶囊组件
// ====================================================================
@interface WCLiquidGlassSegmentBar : UIView
@property (nonatomic, copy) void (^onFilterChanged)(WCLiquidFilterType filterType);
@property (nonatomic, copy) void (^onLongPressed)(void);
@property (nonatomic, assign) WCLiquidFilterType currentFilter;
@property (nonatomic, strong) NSMutableArray<UIButton *> *buttons;
@property (nonatomic, strong) UIView *activeIndicator;
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) CAGradientLayer *glossLayer;
- (void)switchToFilter:(WCLiquidFilterType)filter animate:(BOOL)animate;
@end

@implementation WCLiquidGlassSegmentBar

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.buttons = [NSMutableArray array];
        self.currentFilter = WCLiquidFilterTypeAll;
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.backgroundColor = [UIColor clearColor];

    CGFloat h = self.bounds.size.height;
    CGFloat radius = h / 2.0;

    // 1. 物理实时透视材质 (Live VisualEffect)
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
    self.blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    self.blurView.frame = self.bounds;
    self.blurView.layer.cornerRadius = radius;
    self.blurView.layer.masksToBounds = YES;
    if (@available(iOS 13.0, *)) {
        self.blurView.layer.cornerCurve = kCACornerCurveContinuous;
    }
    self.blurView.userInteractionEnabled = NO;
    [self addSubview:self.blurView];

    // 2. 顶部弧面高光渐变层 (Specular Gloss)
    self.glossLayer = [CAGradientLayer layer];
    self.glossLayer.frame = CGRectMake(0, 0, self.bounds.size.width, h * 0.55);
    self.glossLayer.cornerRadius = radius;
    self.glossLayer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    [self.layer addSublayer:self.glossLayer];

    // 3. 悬浮微阴影
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOpacity = 0.12;
    self.layer.shadowRadius = 8.0;
    self.layer.shadowOffset = CGSizeMake(0, 3);

    // 4. 水滴滑块高光指示器
    CGFloat btnW = (self.bounds.size.width - 8) / 4.0;
    self.activeIndicator = [[UIView alloc] initWithFrame:CGRectMake(4, 4, btnW, h - 8)];
    self.activeIndicator.layer.cornerRadius = (h - 8) / 2.0;
    if (@available(iOS 13.0, *)) {
        self.activeIndicator.layer.cornerCurve = kCACornerCurveContinuous;
    }
    self.activeIndicator.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.35];
    self.activeIndicator.layer.borderWidth = 0.5;
    self.activeIndicator.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.6].CGColor;
    [self addSubview:self.activeIndicator];

    // 5. 四大按钮 (全部 / 好友 / 群聊 / 订阅号)
    NSArray *titles = @[@"全部", @"好友", @"群聊", @"订阅号"];
    for (NSInteger i = 0; i < titles.count; i++) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(4 + i * btnW, 4, btnW, h - 8);
        [btn setTitle:titles[i] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightMedium];
        btn.tag = i;
        [btn addTarget:self action:@selector(btnClicked:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:btn];
        [self.buttons addObject:btn];
    }

    // 6. 长按 0.6 秒秒弹调光设置
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(barLongPressed:)];
    longPress.minimumPressDuration = 0.6;
    [self addGestureRecognizer:longPress];

    [self updateThemeAndStyle];
}

- (void)updateThemeAndStyle {
    BOOL enableLiveBlur = getPrefBool(K_LIVE_BLUR, YES);
    CGFloat blurIntensity = getPrefFloat(K_BLUR_INTENSITY, 0.35);
    BOOL enableSpecular = getPrefBool(K_SPECULAR, YES);
    CGFloat specularIntensity = getPrefFloat(K_SPECULAR_INTENSITY, 0.50);
    BOOL enableRimLight = getPrefBool(K_RIM_LIGHT, YES);
    CGFloat rimWidth = getPrefFloat(K_RIM_WIDTH, 1.0);

    self.blurView.hidden = !enableLiveBlur;
    self.backgroundColor = getDynamicGlassTint(blurIntensity);

    self.layer.borderWidth = enableRimLight ? rimWidth : 0.0;
    self.layer.borderColor = enableRimLight ? getDynamicRimBorderColor().CGColor : nil;
    self.layer.cornerRadius = self.bounds.size.height / 2.0;

    self.glossLayer.hidden = !enableSpecular;
    if (enableSpecular) {
        self.glossLayer.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:(specularIntensity * 0.85)].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:(specularIntensity * 0.25)].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor
        ];
        self.glossLayer.frame = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height * 0.55);
    }

    for (NSInteger i = 0; i < self.buttons.count; i++) {
        UIButton *btn = self.buttons[i];
        BOOL isSel = (i == (NSInteger)self.currentFilter);
        if (@available(iOS 13.0, *)) {
            UIColor *c = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
                BOOL isDark = (traits.userInterfaceStyle == UIUserInterfaceStyleDark);
                if (isSel) {
                    return isDark ? [UIColor colorWithRed:0.35 green:0.75 blue:1.0 alpha:1.0]
                                  : [UIColor colorWithRed:0.00 green:0.45 blue:0.95 alpha:1.0];
                } else {
                    return isDark ? [UIColor colorWithWhite:0.95 alpha:1.0]
                                  : [UIColor colorWithWhite:0.25 alpha:1.0];
                }
            }];
            [btn setTitleColor:c forState:UIControlStateNormal];
        }
    }
}

- (void)switchToFilter:(WCLiquidFilterType)filter animate:(BOOL)animate {
    if (filter < 0 || filter > WCLiquidFilterTypeOfficial) return;
    self.currentFilter = filter;
    CGFloat btnW = (self.bounds.size.width - 8) / 4.0;
    
    void (^updateBlock)(void) = ^{
        self.activeIndicator.frame = CGRectMake(4 + (NSInteger)filter * btnW, 4, btnW, self.bounds.size.height - 8);
    };

    if (animate) {
        [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseInOut animations:updateBlock completion:nil];
    } else {
        updateBlock();
    }
    [self updateThemeAndStyle];

    if (self.onFilterChanged) {
        self.onFilterChanged(self.currentFilter);
    }
}

- (void)btnClicked:(UIButton *)sender {
    [self switchToFilter:(WCLiquidFilterType)sender.tag animate:YES];
}

- (void)barLongPressed:(UILongPressGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) {
        if (@available(iOS 10.0, *)) {
            UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
            [feedback impactOccurred];
        }
        if (self.onLongPressed) {
            self.onLongPressed();
        }
    }
}

@end

// ====================================================================
// 利用微信官方 MainFrameHeaderLogic 挂载 Banner 容器 (永不消失)
// ====================================================================
@interface WCLiquidBannerHolder : MFBannerBtn
@property (nonatomic, strong) WCLiquidGlassSegmentBar *bar;
@end

@implementation WCLiquidBannerHolder

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.layer.backgroundColor = nil;

        CGFloat barW = MIN(frame.size.width - 24, 396);
        CGFloat barX = (frame.size.width - barW) / 2.0;
        self.bar = [[WCLiquidGlassSegmentBar alloc] initWithFrame:CGRectMake(barX, 4, barW, 38)];
        [self addSubview:self.bar];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.backgroundColor = [UIColor clearColor];
    self.layer.backgroundColor = nil;
    [self setBackgroundImage:nil forState:UIControlStateNormal];

    // 抹平父级 Cell 灰色背景
    UIView *parent = self.superview;
    while (parent && ![parent isKindOfClass:[UITableView class]]) {
        parent.backgroundColor = [UIColor clearColor];
        parent.layer.backgroundColor = nil;
        if ([parent isKindOfClass:[UITableViewCell class]]) {
            UITableViewCell *cell = (UITableViewCell *)parent;
            cell.backgroundColor = [UIColor clearColor];
            cell.contentView.backgroundColor = [UIColor clearColor];
            cell.backgroundView = nil;
            cell.selectedBackgroundView = nil;
            if (@available(iOS 14.0, *)) {
                cell.backgroundConfiguration = [UIBackgroundConfiguration clearConfiguration];
            }
        }
        parent = parent.superview;
    }
}

@end

// ====================================================================
// Hook MainFrameLogicController：真实截管微信首页会话数据
// ====================================================================
%hook MainFrameLogicController

- (unsigned int)getSessionCountForSection:(unsigned int)section {
    if (!getPrefBool(K_ENABLED, YES) || gActiveFilter == WCLiquidFilterTypeAll) {
        return %orig;
    }
    updateFilteredSessions();
    return (unsigned int)gFilteredSessions.count;
}

- (id)getSessionInfoAtIndexPath:(NSIndexPath *)indexPath {
    if (!getPrefBool(K_ENABLED, YES) || gActiveFilter == WCLiquidFilterTypeAll) {
        return %orig;
    }
    updateFilteredSessions();
    if (indexPath && indexPath.row < (NSInteger)gFilteredSessions.count) {
        return gFilteredSessions[indexPath.row];
    }
    return %orig;
}

- (id)getCellDataAtIndexPath:(NSIndexPath *)indexPath {
    if (!getPrefBool(K_ENABLED, YES) || gActiveFilter == WCLiquidFilterTypeAll) {
        return %orig;
    }
    updateFilteredSessions();
    // 微信会调用 getCellDataAtIndexPath 来获取每行的显示模型
    return %orig;
}

- (id)indexOfSessionUserName:(NSString *)userName inSection:(unsigned int)section {
    if (!getPrefBool(K_ENABLED, YES) || gActiveFilter == WCLiquidFilterTypeAll) {
        return %orig;
    }
    updateFilteredSessions();
    for (NSUInteger i = 0; i < gFilteredSessions.count; i++) {
        MMSessionInfo *info = gFilteredSessions[i];
        if ([info.m_nsUserName isEqualToString:userName]) {
            return [NSIndexPath indexPathForRow:i inSection:section];
        }
    }
    return %orig;
}

%end

// ====================================================================
// Hook NewMainFrameViewController：原生 Banner 挂载 + 全屏横滑手势
// ====================================================================
static char kBannerHolderKey;

%hook NewMainFrameViewController

- (void)viewDidLoad {
    %orig;

    if (!getPrefBool(K_ENABLED, YES)) return;

    UITableView *table = [self valueForKey:@"m_tableView"];
    MainFrameHeaderLogic *headerLogic = [self valueForKey:@"m_headerLogic"];

    CGFloat w = table ? table.bounds.size.width : [UIScreen mainScreen].bounds.size.width;
    WCLiquidBannerHolder *banner = [[WCLiquidBannerHolder alloc] initWithFrame:CGRectMake(0, 0, w, 46)];

    __weak typeof(self) weakSelf = self;
    banner.bar.onFilterChanged = ^(WCLiquidFilterType type) {
        gActiveFilter = type;
        updateFilteredSessions();
        UITableView *tb = [weakSelf valueForKey:@"m_tableView"];
        [tb reloadData];
    };

    banner.bar.onLongPressed = ^{
        WeChatLiquidTabSettingViewController *vc = [[WeChatLiquidTabSettingViewController alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        [weakSelf presentViewController:nav animated:YES completion:nil];
    };

    // 使用官方微信 Banner 队列挂载
    if (headerLogic && [headerLogic respondsToSelector:@selector(addBannerBtn:atIndex:withAnim:)]) {
        [headerLogic addBannerBtn:banner atIndex:0 withAnim:NO];
    } else if (headerLogic && [headerLogic respondsToSelector:@selector(addBannerBtn:withAnim:)]) {
        [headerLogic addBannerBtn:banner withAnim:NO];
    }

    objc_setAssociatedObject(self, &kBannerHolderKey, banner, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // 全屏左右轻扫滑动手势 (Swipe Left / Right)
    UISwipeGestureRecognizer *swipeLeft = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleLiquidSwipe:)];
    swipeLeft.direction = UISwipeGestureRecognizerDirectionLeft;
    [self.view addGestureRecognizer:swipeLeft];

    UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleLiquidSwipe:)];
    swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
    [self.view addGestureRecognizer:swipeRight];
}

%new
- (void)handleLiquidSwipe:(UISwipeGestureRecognizer *)gesture {
    if (!getPrefBool(K_GESTURE, YES)) return;

    WCLiquidBannerHolder *holder = objc_getAssociatedObject(self, &kBannerHolderKey);
    if (!holder || !holder.bar) return;

    NSInteger cur = (NSInteger)gActiveFilter;
    if (gesture.direction == UISwipeGestureRecognizerDirectionLeft) {
        if (cur < (NSInteger)WCLiquidFilterTypeOfficial) {
            [holder.bar switchToFilter:(WCLiquidFilterType)(cur + 1) animate:YES];
            if (@available(iOS 10.0, *)) {
                UISelectionFeedbackGenerator *fb = [[UISelectionFeedbackGenerator alloc] init];
                [fb selectionChanged];
            }
        }
    } else if (gesture.direction == UISwipeGestureRecognizerDirectionRight) {
        if (cur > (NSInteger)WCLiquidFilterTypeAll) {
            [holder.bar switchToFilter:(WCLiquidFilterType)(cur - 1) animate:YES];
            if (@available(iOS 10.0, *)) {
                UISelectionFeedbackGenerator *fb = [[UISelectionFeedbackGenerator alloc] init];
                [fb selectionChanged];
            }
        }
    }
}

%end
