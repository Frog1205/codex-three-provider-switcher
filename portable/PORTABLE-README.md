# 便携版使用说明

适用于 Windows 10/11 64 位电脑，不需要安装。

1. 必须先完整解压 ZIP，不能直接在压缩包内运行。
2. 双击 `Start-Codex-Switcher.cmd` 打开“Codex API 路由管理器”。
3. 只使用 GPT 官方线路时，不需要配置第三方密钥。
4. 使用 Honknet 或 DeepSeek 前，双击 `Configure-Provider-Keys.cmd`，按提示输入对应密钥。
5. 配置密钥后，完全退出并重新打开 Codex Desktop。

密钥输入过程不会显示字符。密钥只保存到当前 Windows 用户环境变量，不会写入本目录或 Codex `config.toml`。

切回 GPT 官方线路前，必须先完成官方登录：

```powershell
codex login
codex login status
```

切换器会校验 `%USERPROFILE%\.codex\auth.json` 中的登录字段。文件缺失、损坏或只有空 JSON 时，“切换到此线路”按钮会被禁用。

官方额度读取会优先使用 PATH、Codex 沙箱目录或正在运行的桌面版 `codex.exe`。只有找不到原生 CLI 时，才需要安装 Node.js 和 npm 版 Codex CLI：

```powershell
npm install -g @openai/codex
```

DeepSeek 余额显示只需要已配置的 `DEEPSEEK_API_KEY`，不需要 Codex CLI。若显示“暂不可用”，请检查 Key 是否有效以及是否能访问 `https://api.deepseek.com/user/balance`。

Honknet 额度显示使用 `HONKNET_API_KEY`（也兼容 `HONKAI_API_KEY`）调用 `https://ai.honknet.io/api/v1/usage`，默认动态查询当前自然月到今天，不需要 Codex CLI。若显示“暂不可用”，请检查 Key 是否有效以及是否能访问该 usage 接口。

本工具是非官方社区项目，安装包未购买代码签名证书。遇到 Windows SmartScreen 时，请先核对下载来源是本项目 GitHub Releases 页面，再点击“更多信息”与“仍要运行”。
