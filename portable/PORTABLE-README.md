# 便携版使用说明

适用于 Windows 10/11 64 位电脑，不需要安装。

1. 必须先完整解压 ZIP，不能直接在压缩包内运行。
2. 双击 `Start-Codex-Switcher.cmd` 打开切换器。
3. 只使用 GPT 官方线路时，不需要配置第三方密钥。
4. 使用 Honknet 或 DeepSeek 前，双击 `Configure-Provider-Keys.cmd`，按提示输入对应密钥。
5. 配置密钥后，完全退出并重新打开 Codex Desktop。

密钥输入过程不会显示字符。密钥只保存到当前 Windows 用户环境变量，不会写入本目录或 Codex `config.toml`。

如果额度显示为“暂不可用”，请先安装 Node.js 和 npm 版 Codex CLI：

```powershell
npm install -g @openai/codex
```

本工具是非官方社区项目，安装包未购买代码签名证书。遇到 Windows SmartScreen 时，请先核对下载来源是本项目 GitHub Releases 页面，再点击“更多信息”与“仍要运行”。
