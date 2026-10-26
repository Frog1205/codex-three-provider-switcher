# Codex API 路由管理器

一个面向 Windows 和 macOS Apple Silicon Codex Desktop 的 Token · Model 路由切换器。Windows 界面按两类入口组织：官方 OpenAI 与自定义接口；自定义接口内置 Honknet、DeepSeek、OpenDev，并支持继续添加其他兼容接口。

| 类别 | Provider | 默认模型 | 凭据来源 |
| --- | --- | --- | --- |
| 官方 OpenAI | OpenAI 官方账号 | `gpt-5.6-sol` | Codex 已登录的 OpenAI/ChatGPT 账号 |
| 自定义接口 | Honknet | `gpt-5.6-sol` | `HONKNET_API_KEY` 用户环境变量 |
| 自定义接口 | DeepSeek | `deepseek-v4-flash` | `DEEPSEEK_API_KEY` 用户环境变量 |
| 自定义接口 | OpenDev | `gpt-6.1-sol` | `OPENDEV_KEY` 用户环境变量 |

> 这是非官方社区工具。它不会提供、共享或代购任何 API Key，也不会绕过供应商的账号、额度或使用限制。

## 阅读导航：先看你的身份

| 读者 | 推荐阅读 | 目标 |
| --- | --- | --- |
| 👤 普通用户 | [下载与安装](#-普通用户下载与安装)、[日常使用](#-普通用户日常使用)、[常见问题](#-普通用户常见问题) | 安装、配置 Key、查询额度和切换线路 |
| 🤖 Agent / 开发者 | [Agent 快速索引](docs/AGENT-QUICKSTART.md)、[项目结构](#-agent开发者项目结构)、[验证安装](#-agent开发者验证安装)、[开发与贡献](#-agent开发者开发与贡献) | 快速定位代码、测试、配置契约和打包入口 |

普通用户不需要阅读 PowerShell、打包脚本或 Agent 快速索引；Agent 处理任务时应优先读取快速索引，再按需打开源码文件。

## 👤 普通用户：下载与安装

支持两类平台：Windows 10/11 x64，以及 macOS Apple Silicon（M 系列 arm64）。Intel Mac 不支持。

### GitHub Releases 下载

请只从本项目 GitHub Releases 下载：

- [下载安装版 EXE（Windows）](https://github.com/Frog1205/codex-three-provider-switcher/releases/download/v1.4.0/Codex-Three-Provider-Switcher-Setup-x64-V_1.4_261025.01.exe)：自动安装并创建桌面和开始菜单快捷方式。
- [下载免安装便携版 ZIP（Windows）](https://github.com/Frog1205/codex-three-provider-switcher/releases/download/v1.4.0/Codex-Three-Provider-Switcher-Portable-x64-V_1.4_261025.01.zip)：解压后双击启动，不写入安装目录或卸载信息。
- [下载 macOS Apple Silicon 历史稳定版 v1.3 ZIP](https://github.com/Frog1205/codex-three-provider-switcher/releases/download/v1.3.0/Codex-Three-Provider-Switcher-macOS-AppleSilicon-V_1.3_260829.02.zip)：支持 M1/M2/M3/M4/M5 及后续 Apple Silicon，Intel Mac 不支持。
- [查看最新版本与更新说明](https://github.com/Frog1205/codex-three-provider-switcher/releases/latest)

Windows 当前版本为 **v1.4.0 / V_1.4_261025.01**。macOS 仍提供 v1.3 稳定版，本次 Windows 的自定义接口管理功能尚未移植到 macOS。

### EXE 安装版

1. 下载 `Codex-Three-Provider-Switcher-Setup-x64-V_1.4_261025.01.exe`。
2. 双击安装，不需要管理员权限。
3. 安装完成后，双击桌面的“Codex API 路由管理器”。
4. 只使用 GPT 官方线路时无需配置第三方 Key。
5. 使用 Honknet 或 DeepSeek 时，从开始菜单打开“配置 Honknet 和 DeepSeek 密钥”，按提示进行隐藏输入。

### ZIP 免安装版

1. 下载 `Codex-Three-Provider-Switcher-Portable-x64-V_1.3_260829.02.zip`。
2. 右键选择“全部解压”，不能直接在压缩包内运行。
3. 双击 `Start-Codex-Switcher.cmd` 打开切换器。
4. 使用第三方线路前，双击 `Configure-Provider-Keys.cmd` 配置 Key。

### macOS Apple Silicon 版

1. 仅在 M 系列 Mac 上下载并完整解压 `Codex-Three-Provider-Switcher-macOS-AppleSilicon-V_1.3_260829.02.zip`。
2. 双击 `macos/Start-Token-Model-Switch.command`；首次打开时按系统提示允许执行。
3. Intel Mac 不支持此 GUI，启动时会明确提示并退出。
4. 详细的 Python/Tkinter、环境变量和备份说明见 [`macos/README.md`](macos/README.md)。

macOS GUI 同样显示 Official Codex、Honknet、DeepSeek 三路额度卡片；官方额度需要本机安装 npm 版 `@openai/codex` CLI，第三方额度需要对应 shell 环境变量。查询失败只影响额度显示，不影响线路切换。

### Windows 安全提示

本提示适用于 GitHub 提供的未签名 EXE/ZIP 版本。本项目没有为这些文件购买商业代码签名证书，因此 Windows SmartScreen 可能显示“Windows 已保护你的电脑”。请先确认文件来自本仓库的 GitHub Releases，再点击“更多信息”与“仍要运行”。如果下载来源不明，请不要运行。

macOS 版本目前是未签名的 Python/Tkinter GUI。首次双击 `.command` 文件时，如果系统阻止打开，请在“系统设置 → 隐私与安全性”中允许，并确认使用的是 Apple Silicon Mac。

## 👤 普通用户：界面预览（Windows v1.4）

![Codex API 路由管理器 v1.4 离线测试界面](docs/ui-preview-v1.4.png)

![自定义接口编辑窗口](docs/custom-editor-v1.4.png)

以上为离线测试界面，模型与额度为测试占位信息，不代表服务商在线连通性。

### 历史界面（v1.3）

![Codex Provider Switcher V_1.3_260829.02 历史界面](docs/ui-preview-v1.3.png)

`V_1.3_260829.02` 截图仅作历史参考。当前 Windows 版 `V_1.4_261025.01` 已更名为“Codex API 路由管理器”，界面按“官方 OpenAI / 自定义接口”两类入口组织；自定义接口包含 Honknet、DeepSeek、OpenDev 和用户添加的线路。

不同版本的 GUI 外观和变化请查看 [GUI 版本对照](docs/GUI-VERSIONS.md)。

## 👤 普通用户：为什么需要这个工具

这个项目解决的核心问题不是“管理 Codex 登录账号”，而是明确控制 Codex Desktop 下一次启动时使用的 provider 和模型线路。

### 1. 解决中转工具残留导致无法切回官方线路

部分用户长期使用 CC Switch、Codex 路由工具或其他脚本配置中转 API。这些工具可能在 `%USERPROFILE%\.codex\config.toml` 中留下：

- 顶层 `model_provider` 仍指向 `custom` 或其他第三方 provider。
- 第三方 `base_url`、模型目录和 bearer token 配置继续生效。
- 多个工具反复改写同一份配置，导致字段重复、配置错乱或状态难以判断。

后续即使订阅了 Codex 官方账号并完成 OpenAI/ChatGPT 登录，客户端仍可能继续使用原来的中转 provider，看起来像是“官方账号无法登录”或“登录后没有切回官方模型”。这是因为账号授权状态和模型路由配置是两套独立状态：登录成功并不会自动清除第三方 `model_provider`。

本工具在保留官方登录状态、MCP、插件和权限配置的前提下，明确重写顶层 provider/model 路由，并在切换前自动备份，从而稳定切回 GPT Official。

### 2. 官方 Codex 额度不足时快速切换到中转 API

当官方账号额度不足、暂时受限或需要使用其他模型时，可以一键切换到 Honknet 或 DeepSeek 线路，继续通过 Codex Desktop 工作。官方额度恢复后，再点击 `GPT Official` 切回，原有 OpenAI/ChatGPT 登录状态仍然保留。

本项目会读取已登录官方账号返回的 Codex 限额数据，用于显示剩余百分比和重置时间；线路切换仍然是人工一键操作，不会自动在后台更改 provider。切换后必须重启客户端并新建任务，才能明确验证新的线路。

> 不建议让 CC Switch、其他 provider 管理工具和本项目同时改写同一个 `config.toml`。确定使用本项目后，应由一个工具统一管理线路，避免配置再次相互覆盖。

## 👤 普通用户：它会做什么

- 提供一个包含三个按钮的 Windows 桌面窗口。
- 默认使用中文界面，并支持在窗口内即时切换中文和英文。
- 切换前自动备份 `%USERPROFILE%\.codex\config.toml`。
- 只替换顶层模型路由设置，并维护自己的 provider table。
- 保留现有的插件、MCP、权限、features、projects 等其他配置。
- 从 Windows 环境变量读取第三方 Key，不把 Key 写入仓库或 TOML。
- macOS GUI 从 shell 环境变量读取第三方 Key，不把 Key 写入仓库或 TOML。
- Windows GUI 显示官方 Codex、Honknet 和 DeepSeek 的额度/余额，并在窗口打开期间自动刷新。
- macOS GUI 使用独立的 Python/Tkinter 额度读取器，显示官方剩余比例、Honknet 用量和 DeepSeek 余额；不会复用 Windows PowerShell/WinForms 读取器。
- 切换后重启 Codex Desktop；已有任务不会改变 provider，需要新建任务。

## 👤 普通用户：系统要求

### Windows

- Windows 10 或 Windows 11，64 位 x64 电脑。
- Codex Desktop（已正常安装并登录）。
- Windows PowerShell 5.1 或 PowerShell 7。

### macOS Apple Silicon

- macOS 13 或更高版本。
- Apple Silicon（M1/M2/M3/M4/M5 及后续 arm64 芯片）。Intel Mac 不支持。
- Python 3.10+，且包含 Tkinter；推荐使用 python.org 的 macOS 安装包。

### Windows 与 macOS 共通

- 已至少启动并登录过一次 Codex Desktop，使下列文件存在：

```text
%USERPROFILE%\.codex\config.toml
%USERPROFILE%\.codex\auth.json
```

- Honknet 和 DeepSeek 线路需要你自己合法取得的 API Key。
- 第三方服务端必须支持 Codex 使用的 Responses API。只支持 `chat/completions` 的接口不能直接使用本项目默认配置。
- 官方额度显示需要 Node.js 和 npm 版 `@openai/codex` CLI；未安装时三路切换仍可使用，只有 Official 卡片显示 `Unavailable`。
- DeepSeek 余额显示使用官方公开的 `GET https://api.deepseek.com/user/balance`，只需配置 `DEEPSEEK_API_KEY`，不需要额外安装工具。
- Honknet 额度显示使用公开的 `GET https://ai.honknet.io/api/v1/usage`，只需配置 `HONKNET_API_KEY` 或 `HONKAI_API_KEY`，不需要额外安装工具。

macOS 版不需要安装 Node.js 或 Codex CLI 才能切换线路；Node.js/npm 版 CLI 只用于 Official 额度读取，Honknet/DeepSeek 额度直接走公开 HTTPS 接口。

检查 Codex CLI：

```powershell
codex --version
```

需要安装或更新时：

```powershell
npm install -g @openai/codex
```

## 👤 普通用户：重要安全提醒

不要把真实 API Key 填进以下文件：

- `providers.json`
- `config.toml`
- `README.md`
- CMD、PowerShell 脚本或 Git 提交

Windows 安装程序通过隐藏输入读取 Key，并保存到当前 Windows 用户的环境变量；macOS GUI 从 shell 环境变量读取 Key。仓库的 `.gitignore` 也会排除常见密钥和 Codex 本地配置文件，但 `.gitignore` 不是泄密后的补救措施。

## 🤖 Agent/开发者：源码与维护

普通用户优先使用上面的 EXE 安装版或 ZIP 免安装版。以下步骤用于需要审查源码、修改 provider 或参与开发的用户。

### 第一步：登录官方 Codex

先正常打开 Codex Desktop，使用 OpenAI/ChatGPT 账号登录。确认官方模型可以创建新任务并正常回复。

安装程序不会保存或修改你的 OpenAI 登录凭据。官方线路继续使用 Codex 自己的 `auth.json`。

### 第二步：准备第三方 Key

准备以下 Key，按需配置：

- Honknet Key：保存到 `HONKNET_API_KEY`。
- DeepSeek Key：保存到 `DEEPSEEK_API_KEY`。

Key 必须来自对应服务商。请勿使用他人的 Key，也不要把 Key 发到聊天、Issue 或截图中。

### 第三步：下载仓库

使用 Git：

```powershell
git clone https://github.com/Frog1205/codex-three-provider-switcher.git
cd codex-three-provider-switcher
```

也可以在 GitHub 页面点击 **Code > Download ZIP**，解压后进入目录。

### 第四步：运行安装程序

在仓库目录打开 PowerShell：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

安装程序会依次询问是否配置 Honknet 和 DeepSeek Key：

```text
Honknet key is not configured. Configure or replace it now? [y/N]
DeepSeek key is not configured. Configure or replace it now? [y/N]
```

输入 `y` 后按回车，再输入真实 Key。Key 输入过程不会显示字符。

可以只配置其中一个第三方线路。未配置的线路会在切换器中显示 `Missing`，点击时会拒绝修改配置。

安装完成后，文件位于：

```text
%LOCALAPPDATA%\CodexThreeProviderSwitcher
```

桌面会出现：

```text
Codex API Route Manager
```

### 第五步：重启并首次切换

1. 完全退出 Codex Desktop。
2. 重新打开 Codex Desktop一次，使新环境变量进入客户端进程。
3. 保存当前任务中的未提交内容。
4. 双击桌面的 `Codex API 路由管理器`。
5. 点击所需线路。
6. 等待 Codex Desktop 重启。
7. 在客户端中创建一个新任务进行验证。

不要用切换前已经打开的任务判断是否成功。旧任务可能继续保留原会话的 provider 状态。

## 👤 普通用户：手工配置 Key（可选）

### PowerShell 方法

设置 Honknet：

```powershell
[Environment]::SetEnvironmentVariable(
  "HONKNET_API_KEY",
  "你的真实Honknet Key",
  "User"
)
```

设置 DeepSeek：

```powershell
[Environment]::SetEnvironmentVariable(
  "DEEPSEEK_API_KEY",
  "你的真实DeepSeek Key",
  "User"
)
```

验证变量是否存在，不显示 Key：

```powershell
![string]::IsNullOrWhiteSpace(
  [Environment]::GetEnvironmentVariable("HONKNET_API_KEY", "User")
)

![string]::IsNullOrWhiteSpace(
  [Environment]::GetEnvironmentVariable("DEEPSEEK_API_KEY", "User")
)
```

返回 `True` 表示对应变量已配置。

### Windows 图形界面方法

1. 打开“设置”，搜索“环境变量”。
2. 选择“编辑账户的环境变量”。
3. 在“用户变量”区域点击“新建”。
4. 变量名填写 `HONKNET_API_KEY` 或 `DEEPSEEK_API_KEY`。
5. 变量值填写对应的真实 Key。
6. 保存后完全退出并重新打开 Codex Desktop。

`env_key` 不是环境变量本身。它是 Codex `config.toml` 中的字段，用来告诉 Codex应该读取哪个 Windows 环境变量。

## 👤 普通用户：日常使用

桌面窗口显示：

- 当前 provider 和模型。
- Honknet Key 是否存在。
- DeepSeek Key 是否存在。
- DeepSeek 模型目录是否可用。
- 官方 Codex 剩余百分比和重置时间。
- Honknet 今日用量、本月用量和剩余额度。
- DeepSeek 余额、充值余额、赠送余额和 API 可用状态。

默认是中文界面。点击窗口右上角的 `English` 会立即切换全部面板文案、状态提示和弹窗；英文界面中点击 `中文` 可随时切回，不需要重启软件。

三个按钮分别切换到：

- `GPT Official`
- `Honknet`
- `DeepSeek`

每次切换都会在下面的目录创建一份备份：

```text
%USERPROFILE%\.codex\provider-switch-backups
```

### 官方额度显示

窗口打开后会立即读取一次官方 Codex 剩余量，随后每 60 秒刷新。即使当前 provider 是 Honknet 或 DeepSeek，额度读取器也会独立查询已登录的官方账号。

当剩余量从 `0%` 恢复为可用状态时，额度区域会变成绿色并显示：

```text
Official quota is available. You can switch back to GPT Official.
```

本版本只显示和提示，不会自动替你切换 provider。确认额度恢复后，由你点击 `GPT Official`，等待客户端重启并新建任务。

额度读取使用当前 Codex app-server 的 `account/rateLimits/read` 协议。官方公开文档承诺的查看方式是 [usage dashboard](https://chatgpt.com/codex/settings/usage) 和 CLI 会话中的 `/status`；如果后续 Codex 版本调整本地协议，额度区域会降级为 `Unavailable`，不会影响 provider 切换。

### Honknet 额度显示

窗口打开后会使用 `HONKNET_API_KEY`（也兼容 `HONKAI_API_KEY`）调用 Honknet 公开接口 `GET https://ai.honknet.io/api/v1/usage`，默认动态查询当前自然月从月初到今天，时区为 `Asia/Shanghai`，显示剩余额度、今日请求数、今日 tokens、今日费用和本月已用额度，随后每 60 秒自动刷新。Key 不会写入 `config.toml` 或任何项目文件，也不会出现在命令行参数中。

当剩余额度低于 `1 USD`、归零或接口不可用时，Honknet 区域会显示橙色或红色提示；额度充足时显示绿色。本工具只显示和提示，不会自动切换 provider 或自动充值。

也可以手动运行 `powershell.exe -ExecutionPolicy Bypass -File .\Get-HonkaiUsage.ps1` 查看额度。需要自定义日期时使用：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Get-HonkaiUsage.ps1 -StartDate 2026-08-01 -EndDate 2026-08-30 -Timezone Asia/Shanghai -Json
```

### DeepSeek 余额显示

窗口打开后会使用 `DEEPSEEK_API_KEY` 调用 DeepSeek 官方公开接口 `GET https://api.deepseek.com/user/balance`，显示总余额、充值余额、赠送余额和 API 可用状态，随后每 60 秒自动刷新。Key 不会写入 `config.toml` 或任何项目文件，也不会出现在命令行参数中。

当余额低于小额阈值、归零或账号不可用时，DeepSeek 区域会显示红色或橙色提示；余额充足时显示绿色。本工具只显示和提示，不会自动切换 provider 或自动充值。

DeepSeek 官方公开接口只提供余额，不提供网页 [usage](https://platform.deepseek.com/usage) 上的详细用量报表。平台网页用量接口属于登录态私有接口，本项目没有把它作为稳定依赖接入。

也可以手动运行 `powershell.exe -ExecutionPolicy Bypass -File .\Get-DeepSeekBalance.ps1` 查看余额。

自动刷新只在切换器窗口保持打开时运行。关闭窗口后不会安装后台服务或计划任务。

## 🤖 Agent/开发者：命令行与诊断

进入安装目录：

```powershell
cd "$env:LOCALAPPDATA\CodexThreeProviderSwitcher"
```

查看当前状态：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\CodexProviderSwitcher.ps1 -Mode status
```

切换线路：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\CodexProviderSwitcher.ps1 -Mode gpt
powershell.exe -ExecutionPolicy Bypass -File .\CodexProviderSwitcher.ps1 -Mode honkai
powershell.exe -ExecutionPolicy Bypass -File .\CodexProviderSwitcher.ps1 -Mode ds
```

需要直接以英文界面启动时：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\CodexProviderSwitcher.ps1 -Language en
```

不指定 `-Language` 时默认使用 `zh-CN`。

### macOS Apple Silicon 启动

在 Mac 上进入仓库根目录后运行：

```zsh
python3 macos/TokenModelSwitch.py
```

也可以双击 `macos/Start-Token-Model-Switch.command`。Mac GUI 启动时会检查真实硬件能力；Intel Mac 会直接提示不支持。配置逻辑自测命令为：

```zsh
python3 macos/TokenModelSwitch.py --self-test
```

别名对应关系：

| 输入 | 实际线路 |
| --- | --- |
| `gpt`、`official` | GPT Official |
| `honkai`、`honknet` | Honknet |
| `ds`、`deepseek` | DeepSeek |

## 🤖 Agent/开发者：生成的 Codex 配置

Honknet 切换时会自动维护以下 provider。真实 Key 不会出现在 TOML 中：

```toml
[model_providers.honknet]
name = "Honknet"
base_url = "https://sub2api.honknet.io"
env_key = "HONKNET_API_KEY"
wire_api = "responses"
requires_openai_auth = false
```

DeepSeek 切换时会自动维护：

```toml
[model_providers.deepseek]
name = "DeepSeek"
base_url = "https://api.deepseek.com"
env_key = "DEEPSEEK_API_KEY"
wire_api = "responses"
requires_openai_auth = false
```

顶层活动线路设置会随按钮切换，例如：

```toml
model_provider = "honknet"
model = "gpt-5.6-sol"
model_reasoning_effort = "medium"
disable_response_storage = true
```

## 🤖 Agent/开发者：修改 URL 或模型

不同账号、代理或服务商可能使用不同 URL 和模型名。修改仓库中的：

```text
src\providers.json
```

然后重新运行 `Install.ps1`，安装程序会覆盖 `%LOCALAPPDATA%` 中的程序文件，但不会删除 Key、Codex 配置或备份。

常用字段：

| 字段 | 用途 |
| --- | --- |
| `provider_id` | 写入 `model_provider` 的 provider 标识 |
| `model` | 请求的模型 slug |
| `base_url` | 服务商 API 地址 |
| `env_key` | Windows 环境变量名称，不是 Key 值 |
| `wire_api` | 默认是 `responses` |
| `catalog_file` | 可选模型能力目录 |

DeepSeek 默认附带 `deepseek-model-catalog.json`。如果更换模型 slug，模型目录中的 `slug` 也必须匹配。高级用户也可以从 DeepSeek 定义中删除 `catalog_file`，让 Codex 使用默认模型能力，但部分工具能力可能无法正确声明。

## 🤖 Agent/开发者：验证安装

先运行不接触正式配置的自动测试：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Switcher.ps1
```

预期输出：

```text
PASS: syntax, Chinese/English UI, quota reader packaging, aliases, provider/model routing, unrelated config preservation, and backups.
```

真实线路验收清单：

- GPT Official 新任务能正常回复。
- Honknet 新任务能正常回复，且没有 `401` 或环境变量缺失错误。
- DeepSeek 新任务能正常回复，且没有模型目录或协议错误。
- 切换前后 MCP、插件和权限配置仍存在。
- `provider-switch-backups` 每次新增一份备份。

## 👤 普通用户：常见问题

### 显示 `HONKNET_API_KEY is missing`

环境变量没有写入当前 Windows 用户，或 Codex/切换器在设置变量前已经启动。

1. 用上面的只返回 `True/False` 命令检查变量。
2. 完全关闭切换器和 Codex Desktop。
3. 重新打开；仍不生效时注销并重新登录 Windows。

### 显示 `DEEPSEEK_API_KEY is missing`

处理方法与 Honknet 相同。不要把 Key 写进 `providers.json`。

### macOS GUI 无法打开或提示不支持

1. 确认设备是 Apple Silicon（M1/M2/M3/M4/M5 或后续 M 系列），Intel Mac 不支持。
2. 确认已安装 Python 3.10+ 且包含 Tkinter：`python3 -m tkinter` 应能打开测试窗口。
3. 从终端运行 `python3 macos/TokenModelSwitch.py --self-test`，确认配置逻辑正常。
4. 从 Finder 双击启动时，确认 `HONKNET_API_KEY` 和 `DEEPSEEK_API_KEY` 已写入 `~/.zshrc`；GUI 不会读取未继承到进程的临时 shell 变量。

Mac 版使用独立的额度读取器：未安装 Codex CLI 或未配置第三方 Key 时，对应卡片显示 `Unavailable`；这不影响 Token-Model 路由切换。

### 显示 `Official Codex remaining: Unavailable`

这只代表额度查询失败，不影响三个 provider 按钮。依次检查：

1. `codex --version` 是否可以正常运行。
2. `%APPDATA%\npm\node_modules\@openai\codex\bin\codex.js` 是否存在。
3. 官方 Codex 账号是否已经登录。
4. 点击 `Refresh` 重试，或使用官方 [usage dashboard](https://chatgpt.com/codex/settings/usage) 核对。

如果 `codex --version` 报 `Missing optional dependency @openai/codex-win32-x64`，说明全局 `@openai/codex` 安装不完整；执行 `npm install -g @openai/codex@latest` 补齐 Windows 平台二进制后重试。

查询器每个阶段最多等待 8 秒，失败后不会卡住主窗口，并会在下一次自动刷新时重试。

### 显示 Honknet 额度不可用

Honknet 额度查询依赖 `HONKNET_API_KEY` 或 `HONKAI_API_KEY`。依次检查：

1. 环境变量是否已配置，且没有多余引号或空格。
2. 网络是否可以访问 `https://ai.honknet.io/api/v1/usage`。
3. 点击 `Refresh` 重试；如果返回 `HTTP 401` 或 `403`，说明 Key 无效、已过期或没有对应权限。

如果 Honknet 服务端暂未开放该 usage 接口，只会影响额度显示，不影响三个 provider 按钮的线路切换。

### 显示 DeepSeek 余额不可用

DeepSeek 余额查询只依赖 `DEEPSEEK_API_KEY`。依次检查：

1. `DEEPSEEK_API_KEY` 是否已配置，且没有多余引号或空格。
2. 网络是否可以访问 `https://api.deepseek.com/user/balance`。
3. 点击 `Refresh` 重试；如果返回 `HTTP 401`，说明 Key 无效或已过期。

DeepSeek 官方公开接口只返回余额；详细用量报表仍以 [usage](https://platform.deepseek.com/usage) 网页为准。

### 返回 `401` 或 `403`

- Key 无效、已过期或没有对应权限。
- Key 与 `base_url` 不是同一个服务商。
- 环境变量中包含多余引号或空格。

更新 Key 后重启 Codex Desktop。

### 返回 `404`、协议错误或 Responses API 错误

默认配置要求服务端支持 Responses API。部分第三方接口只兼容 OpenAI Chat Completions，不能直接用于 Codex 的该 provider 配置。

核对服务商文档中的：

- `base_url`
- 模型 slug
- Responses API 支持情况

### 点击后还是旧模型

- 仍在使用切换前的旧任务。
- Codex Desktop 没有完全退出。
- 切换器是在 Codex 自己的终端中运行，因此出于安全保护没有自动关闭宿主客户端。

手工关闭 Codex Desktop，重新打开并新建任务。

### `config.toml` 损坏或想回滚

1. 完全关闭 Codex Desktop。
2. 打开 `%USERPROFILE%\.codex\provider-switch-backups`。
3. 找到最近一份正常的 `config-日期时间.toml`。
4. 先备份当前文件，再将正常备份复制为 `%USERPROFILE%\.codex\config.toml`。
5. 重新打开 Codex Desktop。

## 👤 普通用户：卸载

使用 EXE 安装版时，在 Windows“设置 > 应用 > 已安装的应用”中卸载 `Codex API Route Manager`，或使用开始菜单中的卸载入口。卸载程序文件时会保留 Codex 配置、线路备份和环境变量中的 Key。

使用 macOS 版时，删除解压出的项目目录即可。它不会写入系统安装目录；`~/.codex/config.toml`、`~/.codex/provider-switch-backups/` 和 shell 环境变量中的 Key 会保留。

使用源码安装方式时，在仓库目录执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1
```

默认只删除安装目录和桌面快捷方式，保留：

- Windows 环境变量中的 Key。
- Codex `config.toml`。
- provider 配置和历史备份。

同时删除两个用户环境变量：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1 -RemoveCredentials
```

卸载不会自动恢复当前 provider。如需回到官方线路，请先使用切换器点击 `GPT Official`，确认成功后再卸载。

## 🤖 Agent/开发者：项目结构

```text
.
|-- Install.ps1
|-- Uninstall.ps1
|-- README.md
|-- SECURITY.md
|-- LICENSE
|-- docs
|   |-- AGENT-QUICKSTART.md
|   |-- GUI-VERSIONS.md
|   `-- MICROSOFT-STORE.md (维护者/Agent 专用)
|-- packaging
|   |-- Build-Release.ps1
|   |-- CodexThreeProviderSwitcher.iss
|   `-- languages
|       `-- ChineseSimplified.isl
|-- portable
|   |-- Start-Codex-Switcher.cmd
|   |-- Configure-Provider-Keys.cmd
|   `-- PORTABLE-README.md
|-- src
|   |-- CodexProviderSwitcher.ps1
|   |-- ConfigureProviderKeys.ps1
|   |-- Get-CodexRateLimits.ps1
|   |-- Get-DeepSeekBalance.ps1
|   |-- Get-HonkaiUsage.ps1
|   |-- providers.json
|   `-- deepseek-model-catalog.json
|-- macos
|   |-- TokenModelSwitch.py
|   |-- Start-Token-Model-Switch.command
|   `-- README.md
`-- tests
    |-- Test-Switcher.ps1
    `-- Test-Packages.ps1
```

## 🤖 Agent/开发者：开发与贡献

提交 PR 前请运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Switcher.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Packages.ps1
```

安装 Inno Setup 6 后，可复现生成发布文件：

```powershell
winget install --id JRSoftware.InnoSetup --exact
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\packaging\Build-Release.ps1 -Version 1.0.0
```

如需保留历史产物并生成带版本标识的新安装包，可追加 `-ArtifactSuffix`，例如：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\packaging\Build-Release.ps1 -Version 1.4.0 -ArtifactSuffix V_1.4_261025.01
```

这会生成带后缀的 EXE 和 ZIP，不覆盖默认文件名的旧版本产物。

产物位于 `dist`，固定文件名用于 GitHub Releases 的 `latest/download` 链接。安装程序在编译配置中强制要求 Windows 10+ 与 x64 兼容架构。

不要在 Issue、PR、测试 fixture 或日志中提交真实 Key。示例只能使用明确标记为测试用途的占位符。

## 许可证

[MIT](LICENSE)

## 自定义第三方 API 线路

“自定义接口”页中的“管理 / 添加接口”可以查看已保存线路、新增或编辑线路，支持输入：线路名称、唯一 ID、Base URL、模型名、环境变量名、API Key 和协议（`responses` 或 `chat_completions`）。先点“测试连接”，成功后“保存配置”才可用；测试请求分别调用 `/responses` 或 `/chat/completions`，失败不会保存。保存和切换是两个独立操作：

- 把 Key 写入当前 Windows 用户环境变量；Key 不写入仓库、`config.toml` 或自定义线路注册表。
- 把线路定义保存到 `%APPDATA%\CodexThreeProviderSwitcher\custom-providers.json`，其中只保存变量名和路由参数。
- 保存配置不会改变当前路由。选择已保存线路并成功测试后，才可单独点击“切换线路”；切换复用现有的 `config.toml` 原子写入、切换前备份和 Codex 重启流程。

第三方服务必须真正兼容 Codex 所选协议、模型名和工具调用能力。`chat_completions` 仅适用于服务端明确支持的兼容层；如果服务只提供普通聊天接口，不能据此推断可运行 Codex agent/tool loop。保存后需要完全退出并重新打开 Codex，再新建任务验证线路。
