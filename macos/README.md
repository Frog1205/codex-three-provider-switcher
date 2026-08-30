# Token · Model Switch for macOS Apple Silicon

这是 Codex Three-Provider Switcher 的 macOS GUI 版本，只支持 Apple Silicon（M1/M2/M3/M4 等 `arm64` 芯片），Intel Mac 不支持。

## 使用条件

- macOS 13 或更高版本
- Apple Silicon 芯片（M 系列）
- Python 3.10+，且包含 Tkinter（推荐使用 python.org 的 macOS 安装包）
- 已启动并登录过 Codex Desktop，使 `~/.codex/config.toml` 存在

## 启动

1. 从 GitHub 下载 macOS 版本并完整解压。
2. 右键 `Start-Token-Model-Switch.command`，选择“打开”。
3. 如果 macOS 阻止首次打开，请在“系统设置 → 隐私与安全性”中允许，然后再次打开。

也可以在终端运行：

```zsh
python3 macos/TokenModelSwitch.py
```

## 密钥配置

GUI 从 macOS shell 环境变量读取第三方密钥：

```zsh
export HONKNET_API_KEY="your-key"
export DEEPSEEK_API_KEY="your-key"
```

如果从 Finder 双击启动，需要把变量写入 `~/.zshrc` 后重新打开终端和 GUI。GUI 不会显示或写入密钥，只检查是否存在。

## 安全行为

- 只修改 `~/.codex/config.toml` 顶层的模型路由字段。
- 每次切换前自动备份到 `~/.codex/provider-switch-backups/`。
- 不修改 MCP、插件、权限或其他 Codex 配置。
- 切换后需要完全退出并重新打开 Codex Desktop，再新建任务。

## 本地自测

无需打开 GUI 即可运行配置逻辑自测：

```zsh
python3 macos/TokenModelSwitch.py --self-test
```

界面版本与 Windows 版保持一致：`V_1.3_260829.02`。Mac 端只增加平台标识，不改变路由版本规则。
