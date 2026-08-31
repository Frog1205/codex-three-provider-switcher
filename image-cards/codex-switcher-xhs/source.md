# Codex Three-Provider Switcher 小红书图文来源

项目地址：https://github.com/Frog1205/codex-three-provider-switcher

## 项目定位

这是一个面向 Windows 10/11 x64 用户的非官方开源工具，用来在 Codex Desktop 的 GPT Official、Honknet 和 DeepSeek 三条 provider 线路之间切换。

## 解决的核心问题

1. 使用过 CC Switch 或其他中转工具后，本地 `config.toml` 仍残留第三方 provider，导致后来登录官方 Codex 账号仍没有真正切回官方线路。
2. 官方 Codex 额度不足时，需要快速切换到自备的兼容 Responses API 线路继续工作；额度恢复后再切回官方。

## 对小白有用的功能

- 中文界面，支持中英文切换。
- 三个按钮一键切换线路。
- 切换前自动备份 Codex 配置。
- 保留 OpenAI 登录、MCP、插件和权限配置。
- 显示官方 Codex 剩余量和重置时间，每 60 秒刷新。
- Key 通过隐藏输入保存到当前 Windows 用户环境变量，不写进 GitHub 或 TOML。
- 提供 EXE 安装版和 ZIP 免安装版。

## 使用边界

- 非 OpenAI、Honknet 或 DeepSeek 官方产品。
- 不提供、共享、代购或绕过任何 API Key、账号或额度。
- 第三方线路的 Key 需要用户自行合法取得，并且服务端需要兼容 Codex 使用的 Responses API。
- Store/MSIX 版本正在准备和认证，当前从项目 GitHub Releases 下载 EXE 或 ZIP。
- 切换后应等待 Codex Desktop 重启，并新建任务验证新线路。

## 视觉参考

真实界面截图：`docs/assets/codex-provider-switcher.png`
