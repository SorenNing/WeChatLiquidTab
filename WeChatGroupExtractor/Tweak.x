#include <substrate.h>
#include <objc/runtime.h>
#include <objc/message.h>

%class MainFrameLogicController;
%class NewMainFrameViewController;
%class MFBannerBtn;
%class MainFrameHeaderLogic;

%hookf MainFrameLogicController, MainFrameLogicController

// 1. 会话总数过滤
- (unsigned int)getSessionCountForSection:(unsigned int)section {
    // 如果分类功能启用，返回对应分类的会话数
    // 这里简化逻辑：直接返回微信原生数据
    return %orig;
}

// 2. 会话数据获取
- (id)getSessionInfoAtIndexPath:(id)indexPath {
    // 获取原始会话信息
    id info = %orig;
    
    // 如果当前需要过滤（例如只显示群聊）
    // 检查会话类型，如果不是目标类型，返回空或索引偏移
    // 实际生产代码中需要维护一个过滤映射表
    return info;
}

// 3. 单元格数据获取 (核心稳定性)
- (id)getCellDataAtIndexPath:(id)indexPath {
    // WeChatX 使用的是 getCellDataByUsrName: 来查找数据
    // 直接传 indexPath 会导致缓存不一致
    id data = %orig;
    return data;
}

// 4. 会话切换通知处理
- (void)handleWXHomeCategoriesDidChangeNotification:(id)notification {
    %orig;
}

%end

%hook NewMainFrameViewController

// 1. 挂载横幅
- (void)viewDidLoad {
    %orig;
    
    // 获取 Header Logic
    id headerLogic = [self valueForKey:@"m_headerLogic"];
    if (!headerLogic) return;
    
    // 创建 Banner 按钮 (模仿 WeChatX 的逻辑)
    // 关键：使用真实的 MFBannerBtn 类型
    id bannerClass = objc_getClass("MFBannerBtn");
    if (!bannerClass) return;
    
    // 实例化 (需要初始化 frame)
    id banner = [[bannerClass alloc] initWithFrame:CGRectMake(0, 0, 430, 55)];
    if (!banner) return;
    
    // 设置属性 (模仿 WeChatX)
    [banner setTitleText:@"分组"];
    [banner setRightArrowHidden:YES];
    
    // 挂载到微信官方队列
    if ([headerLogic respondsToSelector:@selector(addBannerBtn:atIndex:withAnim:)]) {
        [headerLogic addBannerBtn:banner atIndex:0 withAnim:NO];
    }
}

// 2. 设置左右滑动切换
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    
    // 添加手势支持
    id tableView = [self valueForKey:@"m_tableView"];
    if (!tableView) return;
    
    // 这里实现简单的滑动检测逻辑
    // 实际应该监听手势识别器的变化
}

%end