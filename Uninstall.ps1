param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'CodexThreeProviderSwitcher'),
    [switch]$RemoveCredentials
)

$ErrorActionPreference = 'Stop'
$shell = New-Object -ComObject WScript.Shell
$shortcutPath = Join-Path $shell.SpecialFolders.Item('Desktop') 'Codex Three-Provider Switcher.lnk'
if (Test-Path -LiteralPath $shortcutPath) { Remove-Item -LiteralPath $shortcutPath -Force }
if (Test-Path -LiteralPath $InstallDir) {
    $resolved = [IO.Path]::GetFullPath($InstallDir)
    $expectedRoot = [IO.Path]::GetFullPath($env:LOCALAPPDATA)
    if (-not $resolved.StartsWith($expectedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a directory outside LOCALAPPDATA: $resolved"
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
if ($RemoveCredentials) {
    [Environment]::SetEnvironmentVariable('HONKNET_API_KEY', $null, 'User')
    [Environment]::SetEnvironmentVariable('DEEPSEEK_API_KEY', $null, 'User')
}
Write-Output 'Switcher removed. Existing Codex config and backups were not changed.'
