param(
    [ValidateSet('zh-CN', 'en')]
    [string]$Language = 'zh-CN',
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'

function Send-EnvironmentChanged {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class CodexSwitcherEnvironmentBroadcast {
    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
        uint flags, uint timeout, out UIntPtr result);
}
'@
    $result = [UIntPtr]::Zero
    [void][CodexSwitcherEnvironmentBroadcast]::SendMessageTimeout(
        [IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result)
}

function Set-ProviderKey {
    param(
        [string]$EnvironmentName,
        [string]$DisplayName
    )

    $existing = [Environment]::GetEnvironmentVariable($EnvironmentName, 'User')
    if ($Language -eq 'zh-CN') {
        $state = if ([string]::IsNullOrWhiteSpace($existing)) { '未配置' } else { '已配置' }
        $answer = Read-Host "$DisplayName 密钥当前状态：$state。是否配置或替换？[y/N]"
        if ($answer -notmatch '^(?i)y(?:es)?$') { return }
        $secure = Read-Host "请输入 $DisplayName API Key（输入内容不会显示）" -AsSecureString
    }
    else {
        $state = if ([string]::IsNullOrWhiteSpace($existing)) { 'not configured' } else { 'already configured' }
        $answer = Read-Host "$DisplayName key is $state. Configure or replace it? [y/N]"
        if ($answer -notmatch '^(?i)y(?:es)?$') { return }
        $secure = Read-Host "Enter $DisplayName API key (input is hidden)" -AsSecureString
    }

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        if ([string]::IsNullOrWhiteSpace($plain)) {
            if ($Language -eq 'zh-CN') { throw "$DisplayName 密钥不能为空。" }
            throw "$DisplayName key cannot be empty."
        }
        [Environment]::SetEnvironmentVariable($EnvironmentName, $plain, 'User')
    }
    finally {
        if ($null -ne $plain) { $plain = $null }
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }

    if ($Language -eq 'zh-CN') { Write-Host "$DisplayName 密钥已保存。" -ForegroundColor Green }
    else { Write-Host "$DisplayName key was saved." -ForegroundColor Green }
}

try {
    if ($Language -eq 'zh-CN') {
        Write-Host 'Codex 三线路切换器 - 配置第三方密钥' -ForegroundColor Cyan
        Write-Host '密钥只会保存到当前 Windows 用户环境变量，不会写入项目文件。'
        Write-Host ''
    }
    else {
        Write-Host 'Codex Three-Provider Switcher - Configure provider keys' -ForegroundColor Cyan
        Write-Host 'Keys are stored only in Windows user environment variables, not in project files.'
        Write-Host ''
    }

    Set-ProviderKey 'HONKNET_API_KEY' 'Honknet'
    Set-ProviderKey 'DEEPSEEK_API_KEY' 'DeepSeek'
    Send-EnvironmentChanged

    if ($Language -eq 'zh-CN') {
        Write-Host ''
        Write-Host '配置完成。请完全退出并重新打开 Codex Desktop。' -ForegroundColor Green
    }
    else {
        Write-Host ''
        Write-Host 'Configuration complete. Fully exit and reopen Codex Desktop.' -ForegroundColor Green
    }
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
finally {
    if (-not $NoPause) {
        if ($Language -eq 'zh-CN') { [void](Read-Host '按回车键关闭窗口') }
        else { [void](Read-Host 'Press Enter to close') }
    }
}
