# GUI 版本对照

本页记录 Codex 三线路切换器各版本的界面变化。截图均使用脱敏示例数据，不包含真实 API Key。

## V_1.3_260829.02（当前版本）

![V_1.3_260829.02](ui-preview-v1.3.png)

这是当前推荐版本，定位从“线路切换按钮”升级为 Token · Model 路由管理器：

- 顶部展示软件版本号、当前线路、实际模型和同步状态。
- 当前实际模型使用绿色状态高亮，避免和 Provider 品牌色混淆。
- GPT Official、Honknet、DeepSeek 使用青绿、蓝、紫的浅色卡片和边框进行区分。
- 当前线路使用蓝色选中边框和“当前线路”按钮状态。
- 额度与用量拆成三张卡片，官方额度、Honknet 用量和 DeepSeek 余额一眼可比。

## v1.2.0（上一版）

![v1.2.0](assets/codex-provider-switcher.png)

上一版以纵向信息流为主，功能完整，但线路按钮占据较大的纯色区域，当前线路、模型和额度信息层级不够明显。该版本仍保留在 [GitHub Release v1.2.0](https://github.com/Frog1205/codex-three-provider-switcher/releases/tag/v1.2.0) 中，旧安装包和便携包不会被新版本替换。

## macOS Apple Silicon 版

macOS 版从 v1.3 开始同步提供独立 GUI，界面采用同一套路由卡片、Provider 配色、绿色当前模型状态和三张额度卡片。它只支持 Apple Silicon（M 系列）芯片，Intel Mac 会在启动时拒绝运行；macOS 版不复用 Windows 的 PowerShell/WinForms 额度读取器，而是用 Python 标准库并发查询官方 Codex、Honknet 和 DeepSeek，同时共享同一份 Provider 模型定义和配置备份规则。

## 版本号规则

GUI 版本号使用以下格式：

```text
V_<大版本>.<需求版本>_<YYMMDD>.<当天序号>
```

例如 `V_1.3_260829.02` 表示大版本 1、第三次需求修改、2026-08-29、当天第二次修改。GitHub Release 使用兼容平台排序的三段式版本号（本次为 `v1.3.0`），GUI 和安装包文件名保留完整版本标识。

## 下载对应版本

- 当前版本：[v1.3.0](https://github.com/Frog1205/codex-three-provider-switcher/releases/tag/v1.3.0)
- 上一版本：[v1.2.0](https://github.com/Frog1205/codex-three-provider-switcher/releases/tag/v1.2.0)
