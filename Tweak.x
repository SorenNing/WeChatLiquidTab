#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "SettingViewController.h"

@interface MFBannerBtn : UIButton
@end

@interface NewSettingViewController : UIViewController
@end

@interface WCPluginsViewController : UIViewController
- (id)addNormalCellForSel:(SEL)arg1 title:(id)arg2 rightValue:(id)arg3 userInfo:(id)arg4;
- (void)pushPluginController:(id)arg1;
- (NSMutableArray *)dataSource;
@end

static char kIsGroupTabBtnKey;
#define TRACK_GLASS_TAG 8888
#define BLUR_EFFECT_TAG 8889
#define GLOSS_LAYER_NAME @"LiquidGlossLayer"

#define UD [NSUserDefaults standardUserDefaults]
#define K_ENABLED @"WCLiquid_enabled"
#define K_CLEAR_TRACK @"WCLiquid_clearOuterTrack"
#define K_LIVE_BLUR @"WCLiquid_enableLiveBlur"
#define K_BLUR_INTENSITY @"WCLiquid_blurIntensity"
#define K_SPECULAR @"WCLiquid_enableSpecular"
#define K_SPECULAR_INTENSITY @"WCLiquid_specularIntensity"
#define K_RIM_LIGHT @"WCLiquid_enableRimLight"
#define K_RIM_WIDTH @"WCLiquid_rimBorderWidth"
#define K_HIDE_DOTS @"WCLiquid_hideRedDots"
#define K_INTERCEPT @"WCLiquid_interceptGroup"

static BOOL getPrefBool(NSString *key, BOOL defaultVal) {
    return [UD objectForKey:key] ? [UD boolForKey:key] : defaultVal;
}

static CGFloat getPrefFloat(NSString *key, CGFloat defaultVal) {
    return [UD objectForKey:key] ? [UD floatForKey:key] : defaultVal;
}

// ====================================================================
// 动态颜色适配 (iOS 17 原生动态模式)
// ====================================================================
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
// 1. 微信原生“设置”页面安全右上角入口 (NewSettingViewController)
// ====================================================================
%hook NewSettingViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    UIBarButtonItem *btn = [[UIBarButtonItem alloc] initWithTitle:@"液态玻璃" 
                                                           style:UIBarButtonItemStylePlain 
                                                          target:self 
                                                          action:@selector(openWeChatLiquidTabSettings)];
    self.navigationItem.rightBarButtonItem = btn;
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
                       rightValue:@"0.2.4" 
                         userInfo:nil];
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

- (void)didMoveToWindow {
    %orig;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"WCLiquidSettingsChanged" object:nil];
    if (self.window) {
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(setNeedsLayout) 
                                                     name:@"WCLiquidSettingsChanged" 
                                                   object:nil];
    }
}

- (void)layoutSubviews {
    %orig;

    BOOL enabled = getPrefBool(K_ENABLED, YES);
    BOOL clearOuterTrack = getPrefBool(K_CLEAR_TRACK, YES);
    BOOL enableLiveBlur = getPrefBool(K_LIVE_BLUR, YES);
    CGFloat blurIntensity = getPrefFloat(K_BLUR_INTENSITY, 0.35);
    BOOL enableSpecular = getPrefBool(K_SPECULAR, YES);
    CGFloat specularIntensity = getPrefFloat(K_SPECULAR_INTENSITY, 0.50);
    BOOL enableRimLight = getPrefBool(K_RIM_LIGHT, YES);
    CGFloat rimBorderWidth = getPrefFloat(K_RIM_WIDTH, 1.0);
    BOOL hideRedDots = getPrefBool(K_HIDE_DOTS, NO);

    // ① 如果关闭了全局开关，精准清除所有添加的图层，完全恢复微信原生界面！
    if (!enabled) {
        for (UIView *v in self.subviews) {
            [[v viewWithTag:BLUR_EFFECT_TAG] removeFromSuperview];
            [[v viewWithTag:TRACK_GLASS_TAG] removeFromSuperview];
            v.layer.shadowOpacity = 0.0;
        }
        return;
    }

    // ② 彻底消灭外层灰框跑道（清除自身及父级 Cell 的 UIBackgroundConfiguration）
    if (clearOuterTrack) {
        self.backgroundColor = [UIColor clearColor];
        self.layer.backgroundColor = nil;
        self.layer.borderWidth = 0.0;
        self.layer.shadowOpacity = 0.0;
        if (@available(iOS 15.0, *)) {
            self.configuration = nil;
        }
        [self setBackgroundImage:nil forState:UIControlStateNormal];

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

    // ③ 寻找内部装有 UIStackView 的容器视图
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

        // 长按快捷手势
        if (v.gestureRecognizers.count == 0) {
            UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLiquidBarLongPress:)];
            longPress.minimumPressDuration = 0.6;
            [v addGestureRecognizer:longPress];
        }

        // ④ 实时背景透视材质 (Live Material)
        UIVisualEffectView *blurView = (UIVisualEffectView *)[v viewWithTag:BLUR_EFFECT_TAG];
        if (enableLiveBlur) {
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

        // ⑤ 晶莹水体、边缘倒角与凸面高光层
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

            if (enableRimLight) {
                glassOverlay.layer.borderWidth = rimBorderWidth;
                glassOverlay.layer.borderColor = getDynamicRimBorderColor().CGColor;
            }

            if (enableSpecular) {
                CAGradientLayer *glossLayer = [CAGradientLayer layer];
                glossLayer.name = GLOSS_LAYER_NAME;
                glossLayer.frame = CGRectMake(0, 0, v.bounds.size.width, h * 0.58);
                CGFloat specAlpha = specularIntensity;
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
            glassOverlay.backgroundColor = getDynamicGlassTint(blurIntensity);
            glassOverlay.layer.borderWidth = enableRimLight ? rimBorderWidth : 0.0;
            if (enableRimLight) {
                glassOverlay.layer.borderColor = getDynamicRimBorderColor().CGColor;
            }
            for (CALayer *sublayer in glassOverlay.layer.sublayers) {
                if ([sublayer.name isEqualToString:GLOSS_LAYER_NAME]) {
                    sublayer.frame = CGRectMake(0, 0, v.bounds.size.width, h * 0.58);
                    sublayer.hidden = !enableSpecular;
                    if ([sublayer isKindOfClass:[CAGradientLayer class]]) {
                        CAGradientLayer *gl = (CAGradientLayer *)sublayer;
                        CGFloat specAlpha = specularIntensity;
                        gl.colors = @[
                            (id)[UIColor colorWithWhite:1.0 alpha:(specAlpha * 0.85)].CGColor,
                            (id)[UIColor colorWithWhite:1.0 alpha:(specAlpha * 0.25)].CGColor,
                            (id)[UIColor colorWithWhite:1.0 alpha:0.00].CGColor
                        ];
                    }
                }
            }
        }

        // ⑥ 子视图文字高对比自适应配色与红点
        for (UIView *btnView in stack.arrangedSubviews) {
            if ([btnView isKindOfClass:[UIButton class]]) {
                UIButton *btn = (UIButton *)btnView;
                objc_setAssociatedObject(btn, &kIsGroupTabBtnKey, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

                [btn setTitleColor:getDynamicTextColor(NO) forState:UIControlStateNormal];
                [btn setTitleColor:getDynamicTextColor(YES) forState:UIControlStateSelected];
                btn.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];

                for (UIView *subDot in btn.subviews) {
                    if (subDot != btn.titleLabel && subDot != btn.imageView) {
                        if (subDot.bounds.size.width <= 24 && subDot.bounds.size.height <= 24) {
                            subDot.hidden = hideRedDots;
                        }
                    }
                }
            }
        }
    }
}

%new
- (void)handleLiquidBarLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        if (@available(iOS 10.0, *)) {
            UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
            [feedback impactOccurred];
        }
        WeChatLiquidTabSettingViewController *vc = [[WeChatLiquidTabSettingViewController alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        UIResponder *responder = self;
        while (responder && ![responder isKindOfClass:[UIViewController class]]) {
            responder = responder.nextResponder;
        }
        if ([responder isKindOfClass:[UIViewController class]]) {
            UIViewController *currentVC = (UIViewController *)responder;
            [currentVC presentViewController:nav animated:YES completion:nil];
        }
    }
}

%end

// ====================================================================
// 4. 点击事件拦截
// ====================================================================
%hook UIApplication

- (BOOL)sendAction:(SEL)action to:(id)target from:(id)sender forEvent:(UIEvent *)event {
    BOOL enabled = getPrefBool(K_ENABLED, YES);
    BOOL interceptGroup = getPrefBool(K_INTERCEPT, NO);

    if (enabled && [sender isKindOfClass:[UIButton class]]) {
        NSNumber *isGroupBtn = objc_getAssociatedObject(sender, &kIsGroupTabBtnKey);
        if ([isGroupBtn boolValue]) {
            UIButton *btn = (UIButton *)sender;
            NSString *title = [btn titleForState:UIControlStateNormal];
            if (interceptGroup && [title containsString:@"群聊"]) {
                NSLog(@"[WeChatLiquidTab] 已按设置拦截群聊点击");
                return NO;
            }
        }
    }
    return %orig;
}

%end
