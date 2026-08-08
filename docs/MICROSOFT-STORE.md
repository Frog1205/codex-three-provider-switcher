# Microsoft Store / MSIX 发布指南

本指南用于把 Codex Three-Provider Switcher 发布到 Microsoft Store。目标平台为 Windows 10/11 x64，Store 分发包为 MSIX。

## 先理解两个文件

- `Codex-Three-Provider-Switcher-*-x64-Store.msix` 是提交给 Partner Center 的上传包。它在本地构建时没有商业证书签名，不能作为 GitHub 下载版让用户直接安装。
- 用户最终从 Microsoft Store 得到的 MSIX 会在认证通过后由 Microsoft 重新签名。这个签名不收费，也不需要开发者购买代码签名证书。

Microsoft 不会替 GitHub 上的 EXE、ZIP 或站外分发的 MSIX 签名。现有 EXE/ZIP 继续作为备用下载渠道。

## 第一步：免费注册开发者账号

1. 必须从 [Microsoft Store Developer](https://storedeveloper.microsoft.com/) 点击 **Get started for free**。
2. 选择 **Individual developer**。新个人开发者流程免注册费，适用于微软当前支持的市场。
3. 使用 Microsoft 账号登录并开启 MFA。
4. 按页面要求完成政府证件和自拍验证。
5. 验证完成后进入 Partner Center 的 **Apps and games**。

如果项目实际代表公司、工作室或商业主体发布，应选择 Company，而不是个人账号。

## 第二步：预留应用名称并复制真实标识

1. 在 Partner Center 创建新产品并预留应用名称。
2. 打开产品的 **Product management > Product identity**。
3. 原样复制以下三个值，大小写和标点都不能改：

| 构建参数 | Partner Center 字段 |
| --- | --- |
| `IdentityName` | Package/Identity/Name |
| `Publisher` | Package/Identity/Publisher |
| `PublisherDisplayName` | Package/Properties/PublisherDisplayName |

不要使用 README 示例值提交。Partner Center 的真实标识只有在预留名称后才会生成。

## 第三步：安装本地构建工具

在 64 位 Windows 10/11 上安装：

- Windows 10 SDK 或 Windows 11 SDK，必须包含 `MakeAppx.exe`。
- Windows App Certification Kit，随 Windows SDK 提供。
- Windows 自带的 .NET Framework 4.8 C# 编译器。

推荐从 [Windows SDK 下载页](https://developer.microsoft.com/windows/downloads/windows-sdk/) 安装当前稳定版。安装后重新打开 PowerShell。

验证：

```powershell
Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Filter MakeAppx.exe -Recurse
Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\App Certification Kit" -Filter appcert.exe
```

## 第四步：构建 Store 上传包

在仓库根目录运行，替换三个 Partner Center 值：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\packaging\Build-MSIX.ps1 `
  -IdentityName "Partner Center 的 Identity Name" `
  -Publisher "Partner Center 的 Publisher" `
  -PublisherDisplayName "Partner Center 的 Publisher Display Name" `
  -Version 1.0.0
```

构建脚本会：

- 编译两个 x64 原生入口：切换器和密钥配置器。
- 把 PowerShell 业务逻辑、provider 配置和额度读取器放入包内。
- 生成 Store 所需的 PNG 图标。
- 写入真实包标识和四段式版本号。
- 调用 `MakeAppx.exe` 生成 `dist\Codex-Three-Provider-Switcher-1.0.0.0-x64-Store.msix`。
- 输出文件大小和 SHA-256。

MSIX 的第四段版本号由 Store 保留，本项目构建时固定为 `0`。

## 第五步：认证前检查

必须在干净的 Windows 10 x64 和 Windows 11 x64 机器上分别验证：

- 默认中文界面可打开，英文可切换。
- 能检测官方 Codex 登录和额度。
- 能分别切换 GPT Official、Honknet、DeepSeek。
- 配置密钥入口不会显示或记录明文 Key。
- 切换前会备份 `.codex\config.toml`，且 MCP、插件和权限配置没有丢失。
- Codex Desktop 能正确结束、重启，并要求用户新建任务验证线路。
- 卸载 MSIX 后，不删除用户的 Codex 登录、配置和线路备份。

运行仓库自动测试：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Switcher.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Packages.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-MSIXPackaging.ps1
```

再从开始菜单运行 **Windows App Cert Kit**，对本地测试签名并安装的 MSIX 执行完整认证测试。测试签名只用于本机认证，不上传证书私钥，也不作为 GitHub 发行签名。

## 第六步：填写 Store 页面

至少准备：

- 简短描述和完整描述，中英文各一份。
- 当前 README 中的最终效果截图，另补至少一张英文界面截图。
- 1:1 应用图标、支持邮箱或 GitHub Issues 链接。
- 隐私说明：Key 仅保存在当前 Windows 用户环境变量；不会上传到本项目服务器；应用会读取 Codex 本地配置和官方账号返回的额度数据。
- 年龄分级、类别、市场和定价。建议免费发布。

不要在截图、认证备注或测试账号说明中填写真实 API Key。

## `runFullTrust` 审核说明

本包声明受限能力 `runFullTrust`，因为核心功能需要在当前用户权限下：

- 读取和更新 `%USERPROFILE%\.codex\config.toml`，并先创建备份。
- 读取用户级 `HONKNET_API_KEY` 和 `DEEPSEEK_API_KEY` 环境变量。
- 启动本机 Codex CLI 读取官方额度。
- 在用户确认切换后结束并重新启动 Codex Desktop。

建议在 **Notes for certification** 粘贴以下英文说明，并附上可复现测试步骤：

```text
This is a user-initiated configuration utility for Codex Desktop. The runFullTrust capability is required to back up and update the current user's .codex/config.toml, read user-scoped provider environment variables, invoke the locally installed Codex CLI for official quota display, and restart Codex Desktop after an explicit provider switch. The app never reads, copies, modifies, or distributes Codex auth.json credentials. Provider API keys are never included in the package or transmitted to the publisher.
```

`runFullTrust` 会进入受限能力审核，声明并不保证通过。认证人员可能要求补充操作视频、测试步骤或缩小权限范围。

## 第七步：上传和发布

1. 在 Partner Center 的 submission 中上传生成的 `*-Store.msix`。
2. 完成属性、年龄分级、包、Store listing、定价与可用性等页面。
3. 在认证备注中解释 `runFullTrust`，说明不提供真实 Key 的测试方式。
4. 提交认证。微软文档说明认证过程最长可能需要三个工作日。
5. 只有状态变成 **In the Store** 后，才在 README 增加正式 Store 链接并把 Store 版标记为首选下载。

## GitHub Actions 手动构建

仓库的 **Build Microsoft Store MSIX** 工作流支持手动输入 Partner Center 标识并生成 artifact。GitHub artifact 仍是未签名的 Store 上传包，只能交给仓库维护者提交 Partner Center，不能公开宣传为可安装版本。

## 官方依据

- [个人开发者免费注册](https://learn.microsoft.com/windows/apps/publish/whats-new-individual-developer)
- [MSIX 认证与微软签名](https://learn.microsoft.com/windows/apps/publish/publish-your-app/msix/app-certification-process)
- [MSIX 包要求与 Store 重签名](https://learn.microsoft.com/windows/apps/publish/publish-your-app/msix/app-package-requirements)
- [手工生成桌面 MSIX 与 runFullTrust](https://learn.microsoft.com/windows/msix/desktop/desktop-to-uwp-manual-conversion)
- [Microsoft Store Policies](https://learn.microsoft.com/windows/apps/publish/store-policies)
