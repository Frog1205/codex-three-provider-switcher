param(
    [string]$ArtifactsDir,
    [switch]$Integration
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$installerDefinition = Join-Path $repoRoot 'packaging\CodexThreeProviderSwitcher.iss'
$buildScript = Join-Path $repoRoot 'packaging\Build-Release.ps1'
$keyScript = Join-Path $repoRoot 'src\ConfigureProviderKeys.ps1'
$chineseInstallerLanguage = Join-Path $repoRoot 'packaging\languages\ChineseSimplified.isl'

foreach ($script in @($buildScript, $keyScript)) {
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) { throw "PowerShell syntax errors in $script" }
}

$keyBytes = [IO.File]::ReadAllBytes($keyScript)
if ($keyBytes.Length -lt 3 -or $keyBytes[0] -ne 0xEF -or $keyBytes[1] -ne 0xBB -or $keyBytes[2] -ne 0xBF) {
    throw 'ConfigureProviderKeys.ps1 must use UTF-8 with BOM for Windows PowerShell 5.1.'
}

$iss = [IO.File]::ReadAllText($installerDefinition)
foreach ($required in @('ArchitecturesAllowed=x64compatible', 'ArchitecturesInstallIn64BitMode=x64compatible', 'MinVersion=10.0', 'PrivilegesRequired=lowest')) {
    if (-not $iss.Contains($required)) { throw "Installer requirement is missing: $required" }
}
if (-not (Test-Path -LiteralPath $chineseInstallerLanguage)) { throw 'Simplified Chinese installer messages are missing.' }

foreach ($file in @('Start-Codex-Switcher.cmd', 'Configure-Provider-Keys.cmd', 'PORTABLE-README.md')) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "portable\$file"))) { throw "Portable file is missing: $file" }
}

if (-not [string]::IsNullOrWhiteSpace($ArtifactsDir)) {
    $setup = Join-Path $ArtifactsDir 'Codex-Three-Provider-Switcher-Setup-x64.exe'
    $zip = Join-Path $ArtifactsDir 'Codex-Three-Provider-Switcher-Portable-x64.zip'
    foreach ($artifact in @($setup, $zip)) {
        if (-not (Test-Path -LiteralPath $artifact)) { throw "Release artifact is missing: $artifact" }
        if ((Get-Item -LiteralPath $artifact).Length -lt 1024) { throw "Release artifact is unexpectedly small: $artifact" }
    }
    $header = [IO.File]::ReadAllBytes($setup)
    if ($header[0] -ne 0x4D -or $header[1] -ne 0x5A) { throw 'Installer is not a Windows executable.' }
    $zipEntries = @(tar -tf $zip)
    foreach ($expected in @('Start-Codex-Switcher.cmd', 'Configure-Provider-Keys.cmd', 'src/CodexProviderSwitcher.ps1', 'src/ConfigureProviderKeys.ps1')) {
        if (-not ($zipEntries -match [regex]::Escape($expected))) { throw "Portable archive entry is missing: $expected" }
    }

    if ($Integration) {
        $testRoot = Join-Path $env:TEMP ('codex-switcher-package-test-' + [guid]::NewGuid().ToString('N'))
        $installDir = Join-Path $testRoot 'installed'
        $extractDir = Join-Path $testRoot 'portable'
        [IO.Directory]::CreateDirectory($testRoot) | Out-Null
        $configPath = Join-Path $env:USERPROFILE '.codex\config.toml'
        $configBefore = (Get-FileHash -LiteralPath $configPath).Hash
        $honkBefore = [Environment]::GetEnvironmentVariable('HONKNET_API_KEY', 'User')
        $deepBefore = [Environment]::GetEnvironmentVariable('DEEPSEEK_API_KEY', 'User')

        try {
            $installLog = Join-Path $testRoot 'install.log'
            $installer = Start-Process -FilePath $setup -ArgumentList @(
                '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/TASKS=""',
                "/DIR=`"$installDir`"", "/LOG=`"$installLog`""
            ) -PassThru -Wait
            if ($installer.ExitCode -ne 0) { throw "Installer exit code: $($installer.ExitCode)" }

            foreach ($file in @('CodexProviderSwitcher.ps1', 'Get-CodexRateLimits.ps1', 'ConfigureProviderKeys.ps1', 'providers.json', 'deepseek-model-catalog.json', 'unins000.exe')) {
                if (-not (Test-Path -LiteralPath (Join-Path $installDir $file))) { throw "Installed file is missing: $file" }
            }

            $uninstaller = Start-Process -FilePath (Join-Path $installDir 'unins000.exe') `
                -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -PassThru -Wait
            if ($uninstaller.ExitCode -ne 0) { throw "Uninstaller exit code: $($uninstaller.ExitCode)" }
            Start-Sleep -Seconds 1

            Expand-Archive -LiteralPath $zip -DestinationPath $extractDir
            $portableRoot = Get-ChildItem -LiteralPath $extractDir -Directory | Select-Object -First 1
            if ($null -eq $portableRoot) { throw 'Portable archive root directory was not found.' }
            $statusOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass `
                -File (Join-Path $portableRoot.FullName 'src\CodexProviderSwitcher.ps1') -Mode status -NoRestart | Out-String
            if ($LASTEXITCODE -ne 0 -or $statusOutput -notmatch 'Provider') { throw 'Portable status check failed.' }

            $configAfter = (Get-FileHash -LiteralPath $configPath).Hash
            $honkAfter = [Environment]::GetEnvironmentVariable('HONKNET_API_KEY', 'User')
            $deepAfter = [Environment]::GetEnvironmentVariable('DEEPSEEK_API_KEY', 'User')
            if ($configBefore -ne $configAfter) { throw 'Package integration test changed the formal Codex config.' }
            if ($honkBefore -ne $honkAfter -or $deepBefore -ne $deepAfter) { throw 'Package integration test changed provider credentials.' }
            if (Test-Path -LiteralPath $installDir) { throw 'Silent uninstall did not remove the test installation directory.' }

            Write-Output ('PASS: integration on {0} ({1}), installer and uninstaller exit 0, portable status works, config and credentials unchanged, signature={2}.' -f `
                [Environment]::OSVersion.Version, $(if ([Environment]::Is64BitOperatingSystem) { '64-bit' } else { '32-bit' }), `
                (Get-AuthenticodeSignature -LiteralPath $setup).Status)
        }
        finally {
            if (Test-Path -LiteralPath $testRoot) {
                $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
                $resolvedTemp = [IO.Path]::GetFullPath($env:TEMP)
                if (-not $resolvedTestRoot.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) {
                    throw "Refusing to remove test directory outside TEMP: $resolvedTestRoot"
                }
                Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
            }
        }
    }
}

Write-Output 'PASS: x64 Windows 10+ installer definition, portable launchers, key configurator, and release artifacts.'
