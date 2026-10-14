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

@interface NewMainFrameViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
{
    UITableView *m_tableView;
}
- (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2;
- (long long)tableView:(id)arg1 numberOfRowsInSection:(long long)arg2;
@end

// ====================================================================
// 配置项宏与存取 (NSUserDefaults 微信沙盒安全持久化)
// ====================================================================
#define UD [NSUserDefaults standardUserDefaults]
#define K_ENABLED @"WCLiquid_enabled"
#define K_LIVE_BLUR @"WCLiquid_enableLiveBlur"
#define K_BLUR_INTENSITY @"WCLiquid_blurIntensity"
#define K_SPECULAR @"WCLiquid_enableSpecular"
#define K_SPECULAR_INTENSITY @"WCLiquid_specularIntensity"
#define K_RIM_LIGHT @"WCLiquid_enableRimLight"
#define K_RIM_WIDTH @"WCLiquid_rimBorderWidth"

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
// 独立液态水滴胶囊分组视图 (100% 纯代码手绘，零灰色套娃)
// ====================================================================
typedef NS_ENUM(NSInteger, WCLiquidFilterType) {
    WCLiquidFilterTypeAll = 0,
    WCLiquidFilterTypeFriends,
    WCLiquidFilterTypeGroups,
    WCLiquidFilterTypeOfficial
};

@interface WCLiquidGlassSegmentBar : UIView
@property (nonatomic, copy) void (^onFilterChanged)(WCLiquidFilterType filterType);
@property (nonatomic, copy) void (^onLongPressed)(void);
@property (nonatomic, assign) WCLiquidFilterType currentFilter;
@property (nonatomic, strong) NSMutableArray<UIButton *> *buttons;
@property (nonatomic, strong) UIView *activeIndicator;
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) CAGradientLayer *glossLayer;
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

    // ① 物理实时透视材质 (Live VisualEffect)
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

    // ② 顶部弧面高光渐变层 (Specular Gloss)
    self.glossLayer = [CAGradientLayer layer];
    self.glossLayer.frame = CGRectMake(0, 0, self.bounds.size.width, h * 0.55);
    self.glossLayer.cornerRadius = radius;
    self.glossLayer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    [self.layer addSublayer:self.glossLayer];

    // ③ 水滴微悬浮阴影
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOpacity = 0.12;
    self.layer.shadowRadius = 8.0;
    self.layer.shadowOffset = CGSizeMake(0, 3);

    // ④ 内部水滴指示器滑块
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

    // ⑤ 独立分组按钮 (全部 / 好友 / 群聊 / 公众号)
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

    // ⑥ 长按 0.6 秒秒弹调光设置
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

    // 刷新按钮文字颜色 (深色纯白，浅色深灰)
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

- (void)btnClicked:(UIButton *)sender {
    self.currentFilter = (WCLiquidFilterType)sender.tag;

    CGFloat btnW = (self.bounds.size.width - 8) / 4.0;
    [UIView animateWithDuration:0.28 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.activeIndicator.frame = CGRectMake(4 + sender.tag * btnW, 4, btnW, self.bounds.size.height - 8);
    } completion:nil];

    [self updateThemeAndStyle];

    if (self.onFilterChanged) {
        self.onFilterChanged(self.currentFilter);
    }
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
// Hook 微信主页面：独立注入顶部液态水滴胶囊 + 独立会话分类
// ====================================================================
static WCLiquidFilterType gActiveFilter = WCLiquidFilterTypeAll;
static char kCustomBarKey;

%hook NewMainFrameViewController

- (void)viewDidLoad {
    %orig;

    if (!getPrefBool(K_ENABLED, YES)) return;

    UITableView *table = MSHookIvar<UITableView *>(self, "m_tableView");
    if (!table) return;

    // 自主创建顶部 HeaderView
    UIView *headerContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, table.bounds.size.width, 52)];
    headerContainer.backgroundColor = [UIColor clearColor];

    // 自建独立液态玻璃水滴条 (绝无灰色大跑道)
    CGFloat barW = MIN(table.bounds.size.width - 24, 396);
    CGFloat barX = (table.bounds.size.width - barW) / 2.0;
    WCLiquidGlassSegmentBar *bar = [[WCLiquidGlassSegmentBar alloc] initWithFrame:CGRectMake(barX, 7, barW, 38)];

    __weak typeof(self) weakSelf = self;
    bar.onFilterChanged = ^(WCLiquidFilterType type) {
        gActiveFilter = type;
        UITableView *tb = MSHookIvar<UITableView *>(weakSelf, "m_tableView");
        [tb reloadData];
    };

    bar.onLongPressed = ^{
        WeChatLiquidTabSettingViewController *vc = [[WeChatLiquidTabSettingViewController alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        [weakSelf presentViewController:nav animated:YES completion:nil];
    };

    [headerContainer addSubview:bar];
    table.tableHeaderView = headerContainer;

    objc_setAssociatedObject(self, &kCustomBarKey, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(onLiquidSettingsReload) 
                                                 name:@"WCLiquidSettingsChanged" 
                                               object:nil];
}

%new
- (void)onLiquidSettingsReload {
    WCLiquidGlassSegmentBar *bar = objc_getAssociatedObject(self, &kCustomBarKey);
    if (bar) {
        [bar updateThemeAndStyle];
    }
    UITableView *tb = MSHookIvar<UITableView *>(self, "m_tableView");
    [tb reloadData];
}

%end
