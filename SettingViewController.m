#import "SettingViewController.h"

#define PREF_PATH @"/var/mobile/Library/Preferences/com.soren.wechatliquidtab.plist"
#define NOTIFY_RELOAD "com.soren.wechatliquidtab/Reload"

@interface WeChatLiquidTabSettingViewController ()
@property (nonatomic, strong) NSMutableDictionary *prefs;
@end

@implementation WeChatLiquidTabSettingViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        [self loadPrefs];
    }
    return self;
}

- (void)loadPrefs {
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:PREF_PATH];
    if (dict) {
        self.prefs = [dict mutableCopy];
    } else {
        self.prefs = [NSMutableDictionary dictionary];
    }
    // 默认值
    if (!self.prefs[@"enabled"]) self.prefs[@"enabled"] = @(YES);
    if (!self.prefs[@"clearOuterTrack"]) self.prefs[@"clearOuterTrack"] = @(YES);
    if (!self.prefs[@"enableLiveBlur"]) self.prefs[@"enableLiveBlur"] = @(YES);
    if (!self.prefs[@"blurIntensity"]) self.prefs[@"blurIntensity"] = @(0.35);
    if (!self.prefs[@"enableSpecular"]) self.prefs[@"enableSpecular"] = @(YES);
    if (!self.prefs[@"specularIntensity"]) self.prefs[@"specularIntensity"] = @(0.50);
    if (!self.prefs[@"enableRimLight"]) self.prefs[@"enableRimLight"] = @(YES);
    if (!self.prefs[@"rimBorderWidth"]) self.prefs[@"rimBorderWidth"] = @(1.0);
    if (!self.prefs[@"hideRedDots"]) self.prefs[@"hideRedDots"] = @(NO);
    if (!self.prefs[@"interceptGroup"]) self.prefs[@"interceptGroup"] = @(NO);
}

- (void)savePrefs {
    [self.prefs writeToFile:PREF_PATH atomically:YES];
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR(NOTIFY_RELOAD),
        NULL,
        NULL,
        YES
    );
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
        case 0: return 2; // 核心控制
        case 1: return 6; // 液态质感 (3组开关+滑块)
        case 2: return 2; // 功能定制
        case 3: return 1; // 关于
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
        case 0: return @"开启一体化水滴将彻底清除原本生硬的外层灰框。";
        case 1: return @"采用实时透视材质 + 物理高光与边缘反光倒角，支持深浅模式自适应。";
        case 2: return @"开启后点击群聊分栏将拦截切换。";
        case 3: return @"WeChatLiquidTab v0.2.0 by Soren Ning\n深度调优，即调即生效。";
        default: return nil;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1 && (indexPath.row == 1 || indexPath.row == 3 || indexPath.row == 5)) {
        return 70.0; // 滑块行高
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

    // 辅助创建 Switch
    auto createSwitch = ^(NSString *key) {
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = [self.prefs[key] boolValue];
        [sw addTarget:self action:@selector(switchAction:) forControlEvents:UIControlEventValueChanged];
        objc_setAssociatedObject(sw, "prefKey", key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        cell.accessoryView = sw;
    };

    // 辅助创建 Slider + Value
    auto createSlider = ^(NSString *key, float min, float max, NSString *fmt) {
        UIView *sliderBox = [[UIView alloc] initWithFrame:CGRectMake(16, 0, tableView.bounds.size.width - 32, 64)];
        UILabel *valLbl = [[UILabel alloc] initWithFrame:CGRectMake(sliderBox.bounds.size.width - 70, 4, 60, 20)];
        valLbl.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
        valLbl.textColor = [UIColor secondaryLabelColor];
        valLbl.textAlignment = NSTextAlignmentRight;

        UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 28, sliderBox.bounds.size.width, 30)];
        slider.minimumValue = min;
        slider.maximumValue = max;
        slider.value = [self.prefs[key] floatValue];
        valLbl.text = [NSString stringWithFormat:fmt, slider.value];

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
            createSwitch(@"enabled");
        } else {
            cell.textLabel.text = @"一体化水滴 (消除外圈灰边)";
            createSwitch(@"clearOuterTrack");
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"实时透视模糊 (Live Glass)";
            createSwitch(@"enableLiveBlur");
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"折射与底色浓度";
            createSlider(@"blurIntensity", 0.05, 0.70, @"%.0f%%");
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"凸面弧光高光 (Specular)";
            createSwitch(@"enableSpecular");
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"高光反光强度";
            createSlider(@"specularIntensity", 0.10, 1.00, @"%.0f%%");
        } else if (indexPath.row == 4) {
            cell.textLabel.text = @"晶莹边缘倒角 (Rim Light)";
            createSwitch(@"enableRimLight");
        } else if (indexPath.row == 5) {
            cell.textLabel.text = @"倒角反光粗细";
            createSlider(@"rimBorderWidth", 0.5, 2.5, @"%.1f pt");
        }
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"隐藏分栏小红点";
            createSwitch(@"hideRedDots");
        } else {
            cell.textLabel.text = @"拦截群聊切换";
            createSwitch(@"interceptGroup");
        }
    } else if (indexPath.section == 3) {
        cell.textLabel.text = @"当前版本";
        cell.detailTextLabel.text = @"0.2.0 (roothide)";
    }

    return cell;
}

- (void)switchAction:(UISwitch *)sw {
    NSString *key = objc_getAssociatedObject(sw, "prefKey");
    if (key) {
        self.prefs[key] = @(sw.isOn);
        [self savePrefs];
    }
}

- (void)sliderAction:(UISlider *)slider {
    NSString *key = objc_getAssociatedObject(slider, "prefKey");
    UILabel *lbl = objc_getAssociatedObject(slider, "valLbl");
    NSString *fmt = objc_getAssociatedObject(slider, "fmt");
    if (key) {
        self.prefs[key] = @(slider.value);
        if (lbl && fmt) {
            if ([fmt containsString:@"%%"]) {
                lbl.text = [NSString stringWithFormat:fmt, slider.value * 100.0];
            } else {
                lbl.text = [NSString stringWithFormat:fmt, slider.value];
            }
        }
        [self savePrefs];
    }
}

@end
