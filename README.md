# WeChatGroupExtractor

微信首页独立分组功能的测试实现，位于 `WeChatGroupExtractor` 分支。
基于既有微信私有接口与 WeChatX 二进制调用线索重建，不声称与原插件源码逐字一致。

## 范围

- 简单分组：全部 / 好友 / 群聊 / 订阅号。
- 不包含液态玻璃、模糊、阴影、调光设置页或对第三方插件的运行时依赖。
- 仅向 `com.tencent.xin` 注入。
- 私有微信接口可能随微信版本变化；应在接口不兼容时放弃对应增强，不承诺所有版本兼容。

## 构建

GitHub Actions 使用 macOS、固定提交的 `roothide/theos`（含递归子模块）、固定且校验 SHA-256 的 iPhoneOS 16.5 SDK，以及 `ldid`、GNU make、dpkg。

```sh
export THEOS=/path/to/roothide/theos
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
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
