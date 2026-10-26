# Agent / 开发者快速索引

> 本文给自动化 Agent、维护者和需要审查源码的人阅读。普通用户只需阅读根目录 [README.md](../README.md) 中带“👤 普通用户”标记的章节。

## 先读什么

1. `src/providers.json`：内置线路的 Provider/模型定义来源；Windows 自定义线路位于当前用户 APPDATA 下的注册表文件。
2. `src/CodexProviderSwitcher.ps1`：Windows GUI、路由切换、额度卡片和语言文案。
3. `macos/TokenModelSwitch.py`：macOS Apple Silicon GUI、路由切换和三路额度查询。
4. `tests/Test-Switcher.ps1`、`tests/Test-Packages.ps1`、`tests/Test-MSIXPackaging.ps1`：Windows 回归与打包检查。
5. `macos/test_token_model_switch.py`：macOS 配置和额度解析测试。

## 功能契约

- 只修改 `~/.codex/config.toml`（Windows 为 `%USERPROFILE%\\.codex\\config.toml`）的顶层路由字段，并在切换前备份。
- 不打印、提交或把真实 API Key 写入项目文件、配置或线路元数据。填写变量名时只读取该变量；只填 Key 时自动存入专用 Windows 用户变量，元数据记录 `credential_source=api_key` 和变量引用。旧版无 `credential_source` 的记录继续按环境变量模式读取。
- Provider 标识：`openai`、`honknet`、`deepseek`、`opendev`；Windows 还支持用户自定义 ID；默认模型见 `src/providers.json`。
- 三路额度读取失败必须降级为 `Unavailable`，不能阻断路由切换或冻结 GUI。
- macOS 仅支持 Apple Silicon（arm64/M 系列）；Intel Mac 必须明确拒绝启动。
- 用户切换后必须重启 Codex Desktop 并创建新任务，不能声称已自动切换当前会话。

## 常用验证

在仓库根目录执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Switcher.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-CustomProviders.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\tests\Test-GuiSmoke.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Packages.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-MSIXPackaging.ps1
```

macOS 代码在 Windows 主机上可做静态/逻辑验证：

```powershell
python -m py_compile macos/TokenModelSwitch.py
python macos/TokenModelSwitch.py --self-test
python -m unittest discover -s macos -p 'test_*.py'
```

不要在测试中调用真实额度接口；额度解析测试应使用 mock 响应。

## 发布入口

- Windows 安装包/便携包：`packaging/Build-Release.ps1`
- macOS Apple Silicon ZIP：`packaging/Build-MacOS-Release.ps1`
- MSIX 仅是维护者/Agent 的 Store 上传流程，见 [`MICROSOFT-STORE.md`](MICROSOFT-STORE.md)，不是普通用户下载渠道。
- 版本文件名遵循 `V_<major>.<minor>_<YYMMDD>.<daily-sequence>`，GitHub Release 标签使用兼容排序的三段式版本号。

## 变更检查清单

- 是否保留了其他 Codex 配置（MCP、插件、权限、features、projects）？
- 是否同步更新 `README.md`、`macos/README.md` 或 `docs/GUI-VERSIONS.md`？
- 是否为新行为增加测试，并通过三套 Windows 测试和 Mac Python 测试？
- 是否使用新的版本化资产名，避免覆盖旧 Release 文件？
- 提交前确认 `git status` 中没有 `.env`、`auth.json`、`config.toml` 或真实 Key。
