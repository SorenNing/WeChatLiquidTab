#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "SettingViewController.h"

@interface MFBannerBtn : UIButton
@end

@interface WCTableViewSectionManager : NSObject
+ (id)sectionInfoHeader:(id)arg1;
+ (id)sectionInfoDefaut;
- (void)addCell:(id)arg1;
@end

@interface WCTableViewNormalCellManager : NSObject
+ (id)normalCellForSel:(SEL)arg1 target:(id)arg2 title:(id)arg3 rightValue:(id)arg4 accessoryType:(long long)arg5;
+ (id)normalCellForSel:(SEL)arg1 target:(id)arg2 title:(id)arg3 accessoryType:(long long)arg4;
@end

@interface WCTableViewManager : NSObject
@property (retain, nonatomic) NSMutableArray *sections;
@property (retain, nonatomic) UITableView *tableView;
@end

@interface WCPluginsViewController : UIViewController
- (id)addNormalCellForSel:(SEL)arg1 title:(id)arg2 rightValue:(id)arg3 userInfo:(id)arg4;
- (void)pushPluginController:(id)arg1;
- (void)reloadTableData;
- (NSMutableArray *)dataSource;
@end

static char kIsGroupTabBtnKey;
#define TRACK_GLASS_TAG 8888
#define BLUR_EFFECT_TAG 8889
#define GLOSS_LAYER_NAME @"LiquidGlossLayer"
#define PREF_PATH @"/var/mobile/Library/Preferences/com.soren.wechatliquidtab.plist"
#define NOTIFY_RELOAD "com.soren.wechatliquidtab/Reload"

// ====================================================================
// 配置参数管理
// ====================================================================
static BOOL gEnabled = YES;
static BOOL gClearOuterTrack = YES;
static BOOL gEnableLiveBlur = YES;
static CGFloat gBlurIntensity = 0.35;
static BOOL gEnableSpecular = YES;
static CGFloat gSpecularIntensity = 0.50;
static BOOL gEnableRimLight = YES;
static CGFloat gRimBorderWidth = 1.0;
static BOOL gHideRedDots = NO;
static BOOL gInterceptGroup = NO;

static void loadPrefs(void) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PREF_PATH];
    if (prefs) {
        gEnabled = prefs[@"enabled"] ? [prefs[@"enabled"] boolValue] : YES;
        gClearOuterTrack = prefs[@"clearOuterTrack"] ? [prefs[@"clearOuterTrack"] boolValue] : YES;
        gEnableLiveBlur = prefs[@"enableLiveBlur"] ? [prefs[@"enableLiveBlur"] boolValue] : YES;
        gBlurIntensity = prefs[@"blurIntensity"] ? [prefs[@"blurIntensity"] floatValue] : 0.35;
        gEnableSpecular = prefs[@"enableSpecular"] ? [prefs[@"enableSpecular"] boolValue] : YES;
        gSpecularIntensity = prefs[@"specularIntensity"] ? [prefs[@"specularIntensity"] floatValue] : 0.50;
        gEnableRimLight = prefs[@"enableRimLight"] ? [prefs[@"enableRimLight"] boolValue] : YES;
        gRimBorderWidth = prefs[@"rimBorderWidth"] ? [prefs[@"rimBorderWidth"] floatValue] : 1.0;
        gHideRedDots = prefs[@"hideRedDots"] ? [prefs[@"hideRedDots"] boolValue] : NO;
        gInterceptGroup = prefs[@"interceptGroup"] ? [prefs[@"interceptGroup"] boolValue] : NO;
    }
}

static void prefsNotificationCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    loadPrefs();
}

// ====================================================================
// 动态颜色适配 (iOS 17 原生动态模式)
// ====================================================================
static UIColor *getDynamicGlassTint(void) {
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            if (traits.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor colorWithWhite:1.0 alpha:(gBlurIntensity * 0.25)];
            } else {
                return [UIColor colorWithWhite:1.0 alpha:(gBlurIntensity * 0.75)];
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

static UIColor *getDynamicTextColor(BOOL selected) {
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            BOOL isDark = (traits.userInterfaceStyle == UIUserInterfaceStyleDark);
            if (selected) {
                return isDark ? [UIColor colorWithRed:0.35 green:0.75 blue:1.0 alpha:1.0] 
                              : [UIColor colorWithRed:0.00 green:0.45 blue:0.95 alpha:1.0];
            } else {
                return isDark ? [UIColor colorWithWhite:0.95 alpha:1.0]
                              : [UIColor colorWithWhite:0.20 alpha:1.0];
            }
        }];
    }
    return selected ? [UIColor systemBlueColor] : [UIColor darkGrayColor];
}

// ====================================================================
// 1. 微信原生“设置”页面接入 (NewSettingViewController)
// ====================================================================
%hook NewSettingViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;

    // 1. 递归寻找当前视图树中的 WCTableView
    UITableView *targetTableView = nil;
    for (UIView *sub in self.view.subviews) {
        if ([sub isKindOfClass:[UITableView class]]) {
            targetTableView = (UITableView *)sub;
            break;
        }
    }
    if (!targetTableView) return;

    // 2. 从 targetTableView 获取专属的 WCTableViewManager 数据源
    id mgrObj = targetTableView.dataSource;
    if (!mgrObj || ![mgrObj respondsToSelector:@selector(sections)]) return;

    NSMutableArray *sections = [mgrObj performSelector:@selector(sections)];
    if (!sections || ![sections isKindOfClass:[NSMutableArray class]]) return;

    // 3. 查重，避免重复添加
    BOOL alreadyAdded = NO;
    for (id sec in sections) {
        if ([[sec description] containsString:@"液态玻璃"]) {
            alreadyAdded = YES;
            break;
        }
    }

    if (!alreadyAdded) {
        Class secClass = objc_getClass("WCTableViewSectionManager") ?: objc_getClass("MMTableViewSectionInfo");
        Class cellClass = objc_getClass("WCTableViewNormalCellManager") ?: objc_getClass("MMTableViewCellInfo");

        id sec = nil;
        if ([secClass respondsToSelector:@selector(sectionInfoHeader:)]) {
            sec = [secClass performSelector:@selector(sectionInfoHeader:) withObject:@"插件功能"];
        } else if ([secClass respondsToSelector:@selector(sectionInfoDefaut)]) {
            sec = [secClass performSelector:@selector(sectionInfoDefaut)];
        }

        id cell = nil;
        if ([cellClass respondsToSelector:@selector(normalCellForSel:target:title:rightValue:accessoryType:)]) {
            NSMethodSignature *sig = [cellClass methodSignatureForSelector:@selector(normalCellForSel:target:title:rightValue:accessoryType:)];
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:cellClass];
            [inv setSelector:@selector(normalCellForSel:target:title:rightValue:accessoryType:)];
            SEL actionSel = @selector(openWeChatLiquidTabSettings);
            id targetObj = self;
            NSString *titleStr = @"液态玻璃";
            NSString *valStr = @"0.2.2";
            long long accType = 1;
            [inv setArgument:&actionSel atIndex:2];
            [inv setArgument:&targetObj atIndex:3];
            [inv setArgument:&titleStr atIndex:4];
            [inv setArgument:&valStr atIndex:5];
            [inv setArgument:&accType atIndex:6];
            [inv invoke];
            [inv getReturnValue:&cell];
        }

        if (sec && cell) {
            [sec performSelector:@selector(addCell:) withObject:cell];
            // 插入在通用分组上方 (第1组)
            NSUInteger insertIdx = (sections.count > 1 ? 1 : sections.count);
            [sections insertObject:sec atIndex:insertIdx];
            [targetTableView reloadData];
        }
    }
}

%new
- (void)openWeChatLiquidTabSettings {
    WeChatLiquidTabSettingViewController *vc = [[WeChatLiquidTabSettingViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

%end

// ====================================================================
// 2. 微信内部插件中心接入 (WCPluginsViewController)
// ====================================================================
%hook WCPluginsViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;

    NSMutableArray *ds = [self dataSource];
    BOOL found = NO;
    for (id item in ds) {
        if ([[item description] containsString:@"液态玻璃"]) {
            found = YES;
            break;
        }
    }

    if (!found) {
        [self addNormalCellForSel:@selector(openWeChatLiquidTabSettings) 
                            title:@"液态玻璃" 
                       rightValue:@"0.2.2" 
                         userInfo:nil];
        [self reloadTableData];
    }
}

%new
- (void)openWeChatLiquidTabSettings {
    WeChatLiquidTabSettingViewController *vc = [[WeChatLiquidTabSettingViewController alloc] init];
    if ([self respondsToSelector:@selector(pushPluginController:)]) {
        [self pushPluginController:vc];
    } else if (self.navigationController) {
        [self.navigationController pushViewController:vc animated:YES];
    }
}

%end

// ====================================================================
// 3. 真正的苹果液态玻璃渲染 (MFBannerBtn)
// ====================================================================
%hook MFBannerBtn

- (void)layoutSubviews {
    %orig;

    if (!gEnabled) return;

    // ① 彻底清除外层所有生硬的死板灰圈（向上递归遍历，包括 MMTableViewCell）
    if (gClearOuterTrack) {
        self.backgroundColor = [UIColor clearColor];
        self.layer.backgroundColor = nil;
        self.layer.borderWidth = 0.0;
        self.layer.borderColor = nil;
        self.layer.shadowOpacity = 0.0;
        [self setBackgroundImage:nil forState:UIControlStateNormal];

        // 向上清理所有的父容器背景色，直到列表本身
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
                cell.layer.backgroundColor = nil;
            }
            parent = parent.superview;
        }
    }

    // ② 寻找内部容器
    for (UIView *v in self.subviews) {
        UIStackView *stack = nil;
        for (UIView *sub in v.subviews) {
            if ([sub isKindOfClass:[UIStackView class]]) {
                stack = (UIStackView *)sub;
                break;
            }
        }
        if (!stack) continue;

        CGFloat h = v.bounds.size.height;
        if (h <= 0) continue;
        CGFloat radius = h / 2.0;

        v.backgroundColor = [UIColor clearColor];
        v.layer.backgroundColor = nil;

        // ③ 实时背景透视材质 (Live Material)
        UIVisualEffectView *blurView = (UIVisualEffectView *)[v viewWithTag:BLUR_EFFECT_TAG];
        if (gEnableLiveBlur) {
            if (!blurView) {
                UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
                blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
                blurView.tag = BLUR_EFFECT_TAG;
                blurView.userInteractionEnabled = NO;
                blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                blurView.layer.cornerRadius = radius;
                blurView.layer.masksToBounds = YES;
                if (@available(iOS 13.0, *)) {
                    blurView.layer.cornerCurve = kCACornerCurveContinuous;
                }
                [v insertSubview:blurView atIndex:0];
            }
            blurView.frame = v.bounds;
            blurView.hidden = NO;
        } else if (blurView) {
            blurView.hidden = YES;
        }

        // ④ 晶莹水体、边缘倒角与凸面高光层
        UIView *glassOverlay = [v viewWithTag:TRACK_GLASS_TAG];
        if (!glassOverlay) {
            glassOverlay = [[UIView alloc] initWithFrame:v.bounds];
            glassOverlay.tag = TRACK_GLASS_TAG;
            glassOverlay.userInteractionEnabled = NO;
            glassOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            glassOverlay.layer.cornerRadius = radius;
            glassOverlay.layer.masksToBounds = YES;
            if (@available(iOS 13.0, *)) {
                glassOverlay.layer.cornerCurve = kCACornerCurveContinuous;
            }

            if (gEnableRimLight) {
                glassOverlay.layer.borderWidth = gRimBorderWidth;
                glassOverlay.layer.borderColor = getDynamicRimBorderColor().CGColor;
            }

            if (gEnableSpecular) {
                CAGradientLayer *glossLayer = [CAGradientLayer layer];
                glossLayer.name = GLOSS_LAYER_NAME;
                glossLayer.frame = CGRectMake(0, 0, v.bounds.size.width, h * 0.58);
                CGFloat specAlpha = gSpecularIntensity;
                glossLayer.colors = @[
                    (id)[UIColor colorWithWhite:1.0 alpha:(specAlpha * 0.85)].CGColor,
                    (id)[UIColor colorWithWhite:1.0 alpha:(specAlpha * 0.25)].CGColor,
                    (id)[UIColor colorWithWhite:1.0 alpha:0.00].CGColor
                ];
                glossLayer.locations = @[@0.0, @0.45, @1.0];
                glossLayer.cornerRadius = radius;
                glossLayer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
                [glassOverlay.layer addSublayer:glossLayer];
            }

            v.layer.shadowColor = [UIColor blackColor].CGColor;
            v.layer.shadowOpacity = 0.15;
            v.layer.shadowRadius = 10.0;
            v.layer.shadowOffset = CGSizeMake(0, 3);

            NSUInteger insertIdx = (blurView ? 1 : 0);
            [v insertSubview:glassOverlay atIndex:insertIdx];
        } else {
            glassOverlay.frame = v.bounds;
            glassOverlay.backgroundColor = getDynamicGlassTint();
            glassOverlay.layer.borderWidth = gEnableRimLight ? gRimBorderWidth : 0.0;
            if (gEnableRimLight) {
                glassOverlay.layer.borderColor = getDynamicRimBorderColor().CGColor;
            }
            for (CALayer *sublayer in glassOverlay.layer.sublayers) {
                if ([sublayer.name isEqualToString:GLOSS_LAYER_NAME]) {
                    sublayer.frame = CGRectMake(0, 0, v.bounds.size.width, h * 0.58);
                    sublayer.hidden = !gEnableSpecular;
                    if ([sublayer isKindOfClass:[CAGradientLayer class]]) {
                        CAGradientLayer *gl = (CAGradientLayer *)sublayer;
                        CGFloat specAlpha = gSpecularIntensity;
                        gl.colors = @[
                            (id)[UIColor colorWithWhite:1.0 alpha:(specAlpha * 0.85)].CGColor,
                            (id)[UIColor colorWithWhite:1.0 alpha:(specAlpha * 0.25)].CGColor,
                            (id)[UIColor colorWithWhite:1.0 alpha:0.00].CGColor
                        ];
                    }
                }
            }
        }

        // ⑤ 子视图文字高对比自适应配色
        for (UIView *btnView in stack.arrangedSubviews) {
            if ([btnView isKindOfClass:[UIButton class]]) {
                UIButton *btn = (UIButton *)btnView;
                
                objc_setAssociatedObject(btn, &kIsGroupTabBtnKey, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

                [btn setTitleColor:getDynamicTextColor(NO) forState:UIControlStateNormal];
                [btn setTitleColor:getDynamicTextColor(YES) forState:UIControlStateSelected];
                btn.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];

                // ⑥ 红点控制
                if (gHideRedDots) {
                    for (UIView *subDot in btn.subviews) {
                        if (subDot != btn.titleLabel && subDot != btn.imageView) {
                            if (subDot.bounds.size.width <= 24 && subDot.bounds.size.height <= 24) {
                                subDot.hidden = YES;
                            }
                        }
                    }
                }
            }
        }
    }
}

%end

// ====================================================================
// 4. 点击事件拦截
// ====================================================================
%hook UIApplication

- (BOOL)sendAction:(SEL)action to:(id)target from:(id)sender forEvent:(UIEvent *)event {
    if (gEnabled && [sender isKindOfClass:[UIButton class]]) {
        NSNumber *isGroupBtn = objc_getAssociatedObject(sender, &kIsGroupTabBtnKey);
        if ([isGroupBtn boolValue]) {
            UIButton *btn = (UIButton *)sender;
            NSString *title = [btn titleForState:UIControlStateNormal];

            if (gInterceptGroup && [title containsString:@"群聊"]) {
                NSLog(@"[WeChatLiquidTab] 拦截到群聊切换操作");
                return NO;
            }
        }
    }
    return %orig;
}

%end

// ====================================================================
// 初始化加载
// ====================================================================
%ctor {
    @autoreleasepool {
        loadPrefs();
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            prefsNotificationCallback,
            CFSTR(NOTIFY_RELOAD),
            NULL,
            CFNotificationSuspensionBehaviorCoalesce
        );
    }
}
