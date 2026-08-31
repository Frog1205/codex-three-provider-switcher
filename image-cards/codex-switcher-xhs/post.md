# 小红书发布文案

## 标题

Codex额度不够？三线路一键切

## 正文

最近折腾 Codex Desktop，发现两个很容易踩的坑：

第一，登录了官方账号，不代表本地模型线路已经切回官方。

如果以前用过 CC Switch、路由脚本或其他中转工具，`config.toml` 里可能还留着旧 provider。结果就是账号明明登录成功，新任务却仍然在走中转。

第二，官方 Codex 额度临时用完时，手改配置切备用接口很麻烦；额度恢复后，又容易忘记切回官方。

所以我做了一个 Windows 小工具：Codex Three-Provider Switcher。

目前支持三条线路：

- GPT Official
- Honknet
- DeepSeek

它可以做这些事：

- 三个按钮一键切换线路
- 默认中文界面，也能切换英文
- 切换前自动备份 Codex 配置
- 保留官方登录、MCP、插件和权限
- 显示官方 Codex 剩余量和重置时间
- 官方额度每 60 秒自动刷新，恢复后方便及时切回

小白使用也很简单：

1. 从 GitHub Releases 下载 EXE 安装版或 ZIP 免安装版
2. 使用第三方线路时，只配置自己合法取得的 Key
3. 保存当前任务，点击线路按钮，等待 Codex 重启后新建任务

安全边界也说清楚：

- Key 不会写进仓库或 `config.toml`
- 工具不读取、复制或修改 `auth.json`
- 不提供、共享、代购或绕过任何账号、Key 和额度
- 第三方服务必须兼容 Codex 使用的 Responses API

这是一个非官方开源社区工具，MIT License。

项目地址：
https://github.com/Frog1205/codex-three-provider-switcher

Microsoft Store / MSIX 版本正在准备中。当前请只从项目 GitHub Releases 下载，不要使用来源不明的二次打包版本。

你更需要“切回官方”，还是“官方额度不足时切备用”？评论区可以交流配置问题，但不要粘贴任何 API Key。

## 标签

#Codex #AI工具 #开源项目 #Windows软件 #程序员工具 #效率工具 #DeepSeek #GitHub

## 配图顺序

1. `01-cover-three-provider-switch.png`
2. `02-content-login-vs-route.png`
3. `03-content-providers-and-quota.png`
4. `04-content-three-easy-steps.png`
5. `05-ending-safety-and-github.png`
