#import "SettingViewController.h"
#import <objc/runtime.h>

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

@implementation WeChatLiquidTabSettingViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"液态玻璃";
    if (@available(iOS 13.0, *)) {
        self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    }
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 2;
        case 1: return 6;
        case 2: return 2;
        case 3: return 1;
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"核心控制";
        case 1: return @"苹果原生液态质感微调";
        case 2: return @"交互与功能";
        case 3: return @"关于";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"开启一体化水滴将彻底清除原本生硬的外层灰色跑道。";
        case 1: return @"支持 iOS 实时背景物理透视与高光反光倒角，即调即生效。";
        case 2: return @"开启后点击群聊分栏将拦截切换。";
        case 3: return @"WeChatLiquidTab v0.2.4 by Soren Ning\n原生本地存储，即调即生效。";
        default: return nil;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1 && (indexPath.row == 1 || indexPath.row == 3 || indexPath.row == 5)) {
        return 70.0;
    }
    return 50.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellId = [NSString stringWithFormat:@"Cell_%ld_%ld", (long)indexPath.section, (long)indexPath.row];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellId];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }

    void (^createSwitch)(NSString *, BOOL) = ^(NSString *key, BOOL defaultVal) {
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = [UD objectForKey:key] ? [UD boolForKey:key] : defaultVal;
        [sw addTarget:self action:@selector(switchAction:) forControlEvents:UIControlEventValueChanged];
        objc_setAssociatedObject(sw, "prefKey", key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        cell.accessoryView = sw;
    };

    void (^createSlider)(NSString *, float, float, float, NSString *) = ^(NSString *key, float defaultVal, float min, float max, NSString *fmt) {
        UIView *sliderBox = [[UIView alloc] initWithFrame:CGRectMake(16, 0, tableView.bounds.size.width - 32, 64)];
        UILabel *valLbl = [[UILabel alloc] initWithFrame:CGRectMake(sliderBox.bounds.size.width - 70, 4, 60, 20)];
        valLbl.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
        valLbl.textColor = [UIColor secondaryLabelColor];
        valLbl.textAlignment = NSTextAlignmentRight;

        UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 28, sliderBox.bounds.size.width, 30)];
        slider.minimumValue = min;
        slider.maximumValue = max;
        slider.value = [UD objectForKey:key] ? [UD floatForKey:key] : defaultVal;
        
        if ([fmt containsString:@"%%"]) {
            valLbl.text = [NSString stringWithFormat:fmt, slider.value * 100.0];
        } else {
            valLbl.text = [NSString stringWithFormat:fmt, slider.value];
        }

        [slider addTarget:self action:@selector(sliderAction:) forControlEvents:UIControlEventValueChanged];
        objc_setAssociatedObject(slider, "prefKey", key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(slider, "valLbl", valLbl, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(slider, "fmt", fmt, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        [sliderBox addSubview:valLbl];
        [sliderBox addSubview:slider];
        [cell.contentView addSubview:sliderBox];
    };

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"启用液态玻璃";
            createSwitch(K_ENABLED, YES);
        } else {
            cell.textLabel.text = @"一体化水滴 (消除外圈灰边)";
            createSwitch(K_CLEAR_TRACK, YES);
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"实时透视模糊 (Live Glass)";
            createSwitch(K_LIVE_BLUR, YES);
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"折射与底色浓度";
            createSlider(K_BLUR_INTENSITY, 0.35, 0.05, 0.70, @"%.0f%%");
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"凸面弧光高光 (Specular)";
            createSwitch(K_SPECULAR, YES);
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"高光反光强度";
            createSlider(K_SPECULAR_INTENSITY, 0.50, 0.10, 1.00, @"%.0f%%");
        } else if (indexPath.row == 4) {
            cell.textLabel.text = @"晶莹边缘倒角 (Rim Light)";
            createSwitch(K_RIM_LIGHT, YES);
        } else if (indexPath.row == 5) {
            cell.textLabel.text = @"倒角反光粗细";
            createSlider(K_RIM_WIDTH, 1.0, 0.5, 2.5, @"%.1f pt");
        }
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"隐藏分栏小红点";
            createSwitch(K_HIDE_DOTS, NO);
        } else {
            cell.textLabel.text = @"拦截群聊切换";
            createSwitch(K_INTERCEPT, NO);
        }
    } else if (indexPath.section == 3) {
        cell.textLabel.text = @"当前版本";
        cell.detailTextLabel.text = @"0.2.4 (roothide)";
    }

    return cell;
}

- (void)switchAction:(UISwitch *)sw {
    NSString *key = objc_getAssociatedObject(sw, "prefKey");
    if (key) {
        [UD setBool:sw.isOn forKey:key];
        [UD synchronize];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"WCLiquidSettingsChanged" object:nil];
    }
}

- (void)sliderAction:(UISlider *)slider {
    NSString *key = objc_getAssociatedObject(slider, "prefKey");
    UILabel *lbl = objc_getAssociatedObject(slider, "valLbl");
    NSString *fmt = objc_getAssociatedObject(slider, "fmt");
    if (key) {
        [UD setFloat:slider.value forKey:key];
        [UD synchronize];
        if (lbl && fmt) {
            if ([fmt containsString:@"%%"]) {
                lbl.text = [NSString stringWithFormat:fmt, slider.value * 100.0];
            } else {
                lbl.text = [NSString stringWithFormat:fmt, slider.value];
            }
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:@"WCLiquidSettingsChanged" object:nil];
    }
}

@end
