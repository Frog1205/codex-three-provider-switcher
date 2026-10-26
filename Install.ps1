param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'CodexThreeProviderSwitcher'),
    [switch]$SkipCredentials,
    [switch]$NoShortcut
)

$ErrorActionPreference = 'Stop'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Set-SecretFromPrompt {
    param([string]$EnvironmentName, [string]$DisplayName)

    $existing = [Environment]::GetEnvironmentVariable($EnvironmentName, 'User')
    $state = if ([string]::IsNullOrWhiteSpace($existing)) { 'not configured' } else { 'already configured' }
    $answer = Read-Host "$DisplayName key is $state. Configure or replace it now? [y/N]"
    if ($answer -notmatch '^(?i)y(?:es)?$') { return }
    $secure = Read-Host "Enter $DisplayName API key (input is hidden)" -AsSecureString
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        if ([string]::IsNullOrWhiteSpace($plain)) { throw "$DisplayName key cannot be empty." }
        [Environment]::SetEnvironmentVariable($EnvironmentName, $plain, 'User')
    }
    finally {
        if ($null -ne $plain) { $plain = $null }
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
    Write-Output "$EnvironmentName configured for the current Windows user."
}

function Send-EnvironmentChanged {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class EnvironmentBroadcast {
    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
        uint flags, uint timeout, out UIntPtr result);
}
'@
    $result = [UIntPtr]::Zero
    [void][EnvironmentBroadcast]::SendMessageTimeout(
        [IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result)
}

$sourceDir = Join-Path $PSScriptRoot 'src'
foreach ($required in @('CodexProviderSwitcher.ps1', 'Get-CodexRateLimits.ps1', 'Get-DeepSeekBalance.ps1', 'Get-HonkaiUsage.ps1', 'providers.json', 'deepseek-model-catalog.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceDir $required))) {
        throw "Package file is missing: $required"
    }
}

[IO.Directory]::CreateDirectory($InstallDir) | Out-Null
# Recurse: copy every file under src/ (including assets/, etc.) to $InstallDir,
# preserving relative subpath so e.g. src/assets/codex-switcher-icon.ico
# lands at $InstallDir/assets/codex-switcher-icon.ico.
foreach ($file in @(Get-ChildItem -LiteralPath $sourceDir -Recurse -File)) {
    $rel = $file.FullName.Substring($sourceDir.Length).TrimStart('\', '/')
    $dest = if ($rel) { Join-Path $InstallDir $rel } else { $InstallDir }
    $destDir = Split-Path -Path $dest -Parent
    if (-not (Test-Path -LiteralPath $destDir)) {
        [IO.Directory]::CreateDirectory($destDir) | Out-Null
    }
    [IO.File]::Copy($file.FullName, $dest, $true)
}

$codexCliEntry = Join-Path $env:APPDATA 'npm\node_modules\@openai\codex\bin\codex.js'
if (Test-Path -LiteralPath $codexCliEntry) {
    Write-Output 'Official Codex quota display: Ready'
}
else {
    Write-Warning 'Official Codex quota display needs the npm @openai/codex CLI. Provider switching will still work.'
}

if (-not $SkipCredentials) {
    Set-SecretFromPrompt 'HONKNET_API_KEY' 'Honknet'
    Set-SecretFromPrompt 'DEEPSEEK_API_KEY' 'DeepSeek'
    Send-EnvironmentChanged
}

if (-not $NoShortcut) {
    $shell = New-Object -ComObject WScript.Shell
    $desktop = $shell.SpecialFolders.Item('Desktop')
    $shortcutPath = Join-Path $desktop 'Codex API 路由管理器.lnk'
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $scriptPath = Join-Path $InstallDir 'CodexProviderSwitcher.ps1'
    $shortcut.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$scriptPath`""
    $shortcut.WorkingDirectory = $InstallDir
    $shortcut.IconLocation = Join-Path $InstallDir 'assets\codex-switcher-icon.ico'
    $shortcut.Description = 'Manage official OpenAI and custom Codex API routes'
    $shortcut.WindowStyle = 7
    $shortcut.Save()
    $legacyShortcut = Join-Path $desktop 'Codex Three-Provider Switcher.lnk'
    if (Test-Path -LiteralPath $legacyShortcut) { Remove-Item -LiteralPath $legacyShortcut -Force }
    Write-Output "Desktop shortcut: $shortcutPath"
}

Write-Output "Installed to: $InstallDir"
Write-Output 'Installation complete. Restart Codex Desktop before the first provider switch.'
