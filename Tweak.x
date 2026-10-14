#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static char kIsGroupTabBtnKey;
#define LIQUID_GLASS_TAG 8888

// ====================================================================
// 1. 液态玻璃质感渲染 (MFBannerBtn)
// ====================================================================
%hook MFBannerBtn

- (void)layoutSubviews {
    %orig;

    for (UIView *v in self.subviews) {
        // 寻找直接包裹 UIStackView 的容器视图
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

        // 清除原有微信底框的死板纯灰底色
        v.backgroundColor = [UIColor clearColor];

        // 注入液态玻璃核心层（仅一次）
        UIView *liquidGlass = [v viewWithTag:LIQUID_GLASS_TAG];
        if (!liquidGlass) {
            liquidGlass = [[UIView alloc] initWithFrame:v.bounds];
            liquidGlass.tag = LIQUID_GLASS_TAG;
            liquidGlass.userInteractionEnabled = NO;
            liquidGlass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

            // [透亮水体质感] 半透明清透基底
            liquidGlass.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
            liquidGlass.layer.cornerRadius = radius;
            liquidGlass.layer.masksToBounds = YES;

            // [晶莹边缘倒角] 细致的高透光高亮微边
            liquidGlass.layer.borderWidth = 1.0;
            liquidGlass.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.65].CGColor;

            // [凸面弧光反光] 顶部月牙形高光渐变
            CAGradientLayer *glossLayer = [CAGradientLayer layer];
            glossLayer.frame = CGRectMake(0, 0, v.bounds.size.width, h * 0.55);
            glossLayer.colors = @[
                (id)[UIColor colorWithWhite:1.0 alpha:0.45].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.15].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor
            ];
            glossLayer.locations = @[@0.0, @0.5, @1.0];
            glossLayer.cornerRadius = radius;
            glossLayer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
            [liquidGlass.layer addSublayer:glossLayer];

            // [环境光悬浮阴影]
            v.layer.shadowColor = [UIColor blackColor].CGColor;
            v.layer.shadowOpacity = 0.08;
            v.layer.shadowRadius = 8.0;
            v.layer.shadowOffset = CGSizeMake(0, 3);

            [v insertSubview:liquidGlass atIndex:0];
        } else {
            liquidGlass.frame = v.bounds;
        }

        // 定制按钮视觉与绑定拦截标记
        for (UIView *btnView in stack.arrangedSubviews) {
            if ([btnView isKindOfClass:[UIButton class]]) {
                UIButton *btn = (UIButton *)btnView;
                
                // 关联打标，供后面精准拦截
                objc_setAssociatedObject(btn, &kIsGroupTabBtnKey, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

                // 文字配色优化
                [btn setTitleColor:[UIColor colorWithWhite:0.25 alpha:1.0] forState:UIControlStateNormal];
                [btn setTitleColor:[UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0] forState:UIControlStateSelected];
                btn.titleLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightMedium];
            }
        }
    }
}

%end


// ====================================================================
// 2. 拦截切换事件 (统一点击总路由)
// ====================================================================
%hook UIApplication

- (BOOL)sendAction:(SEL)action to:(id)target from:(id)sender forEvent:(UIEvent *)event {
    if ([sender isKindOfClass:[UIButton class]]) {
        NSNumber *isGroupBtn = objc_getAssociatedObject(sender, &kIsGroupTabBtnKey);
        if ([isGroupBtn boolValue]) {
            UIButton *btn = (UIButton *)sender;
            NSString *title = [btn titleForState:UIControlStateNormal];

            NSLog(@"[WeChatLiquidTab] 捕获点击: [%@] -> Target: %@, Action: %@", 
                  title, [target class], NSStringFromSelector(action));

            // 示例：如果想要阻止切到“群聊”，解除下面注释即可
            /*
            if ([title containsString:@"群聊"]) {
                NSLog(@"[WeChatLiquidTab] 阻止切换到群聊");
                return NO;
            }
            */
        }
    }
    return %orig;
}

%end
