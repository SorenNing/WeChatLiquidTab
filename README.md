# WeChatGroupExtractor

微信首页独立分组功能的测试实现，位于 `WeChatGroupExtractor` 分支。
基于既有微信私有接口与 WeChatX 二进制调用线索重建，不声称与原插件源码逐字一致。

## 范围

- 简单分组：全部 / 好友 / 群聊 / 订阅号。
- 不包含液态玻璃、模糊、阴影、调光设置页或对第三方插件的运行时依赖。
- 仅向 `com.tencent.xin` 注入。
- 私有微信接口可能随微信版本变化；应在接口不兼容时放弃对应增强，不承诺所有版本兼容。

## 0.0.3 入口与开关

- **微信 → 我 → 设置 → 右上角“分组设置”**。这是导航栏按钮，不是微信列表内新增一行；不改微信私有设置表格模型。
- 分组条末尾也有“设置”按钮。原生横幅无法显示时，使用首页导航栏标题位置作为备用分组条；不替换会话表格 dataSource/delegate。
- 设置包含启用分组、好友中排除系统会话、调试日志、运行状态、重新检测与挂载、复制诊断信息。开关写在微信沙盒 NSUserDefaults 内；无玻璃参数。
- 设置入口 hook 与分组数据源 hook 解耦。数据接口不兼容时仍应能打开设置和复制诊断，不会强行取消 ABI 检查。
- 初始化、回到前台、首页 viewDidLoad/viewDidAppear 及 0/1/3/8/15/30 秒重试检查挂载；重试不重复插入可能已部分成功的原生横幅队列。
- 0.0.2 把 `indexOfSessionUserName:inSection:` 强制当成对象返回，导致整数返回版本不能启用。0.0.3 接受受支持的 64 位整数行号或对象签名，计数返回/section 参数宽度独立判断。

如果**两个入口都没有**，先确认实际安装包版本是 0.0.3，彻底退出微信再打开，并核实 RootHide 的微信注入。入口不存在不能仅靠设置页重试解决；请反馈微信版本与安装/注入状态。

## 构建

GitHub Actions 使用 macOS、固定提交的 `roothide/theos`（含递归子模块）、固定且校验 SHA-256 的 iPhoneOS 16.5 SDK，以及 `ldid`、GNU make、dpkg。

```sh
export THEOS=/path/to/roothide/theos
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
cc -std=c11 -Wall -Wextra -Werror test_abi.c -o /tmp/wg-test-abi
/tmp/wg-test-abi
python3 -m unittest test_audit -v
python3 audit_package.py packages/*.deb --output audit.json
```

包结构门禁覆盖：包 ID/架构、仅微信过滤配置、安装文件白名单、无维护脚本、ARM64E dylib、真实系统库依赖、roothide Substrate 路径与 install name、chained fixups 和签名命令存在性。

**门禁不验证实际签名有效性，也不验证微信私有 ABI、动态挂载、会话刷新、交互与长期稳定性。构建成功不代表真机通过。**

## 安装前

此分支是测试候选，不应与旧 `com.soren.wechatliquidtab` 共载；包声明了 Conflicts。安装器若提出移除旧插件，由用户决定，不会在此工作流中自动安装或卸载任何插件。

同时关闭其它会话分组/过滤插件，避免多个插件同时重定向同一数据源。通过 RootHide Manager 启用微信注入后，再由用户重新打开微信。

## 最小真机验证

1. 先验证“全部”和未装插件时会话数、顺序、会话点击一致。
2. 分别选择好友、群聊和订阅号，确认显示内容与点击进入的会话一致；特殊会话不应被误认作普通好友。
3. 切换回“全部”，检查没有丢失会话。
4. 在过滤状态收消息、置顶/取消置顶、删除会话、进入/返回聊天，检查刷新后索引仍一致。
5. 上下滚动、下拉小程序、退出首页再返回、旋转/布局变化时检查分组条。
6. 遇到闪退、错会话、空白行、卡顿时停止测试，关闭此插件注入并保留崩溃日志；请提供微信版本、实际包版本和最短复现步骤。

静态分析无法代替这些步骤，不使用“绝不闪退”或“永久稳定”等保证。
