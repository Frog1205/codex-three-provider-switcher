param(
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version = '1.0.0',
    [string]$OutputDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist'),
    [string]$IsccPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$outputFullPath = [IO.Path]::GetFullPath($OutputDir)
[IO.Directory]::CreateDirectory($outputFullPath) | Out-Null

if ([string]::IsNullOrWhiteSpace($IsccPath)) {
    $isccCandidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
    )
    $IsccPath = $isccCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if ([string]::IsNullOrWhiteSpace($IsccPath) -or -not (Test-Path -LiteralPath $IsccPath)) {
    throw 'Inno Setup 6 compiler was not found. Install JRSoftware.InnoSetup with winget.'
}

$portableName = 'Codex-Three-Provider-Switcher-Portable-x64'
$portableZip = Join-Path $outputFullPath "$portableName.zip"
$setupExe = Join-Path $outputFullPath 'Codex-Three-Provider-Switcher-Setup-x64.exe'
$stagingRoot = Join-Path $env:TEMP ('codex-switcher-release-' + [guid]::NewGuid().ToString('N'))
$portableRoot = Join-Path $stagingRoot $portableName

try {
    [IO.Directory]::CreateDirectory($portableRoot) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $portableRoot 'src')) | Out-Null

    foreach ($file in @('CodexProviderSwitcher.ps1', 'Get-CodexRateLimits.ps1', 'ConfigureProviderKeys.ps1', 'providers.json', 'deepseek-model-catalog.json')) {
        [IO.File]::Copy((Join-Path $repoRoot "src\$file"), (Join-Path $portableRoot "src\$file"), $true)
    }
    foreach ($file in @('Start-Codex-Switcher.cmd', 'Configure-Provider-Keys.cmd', 'PORTABLE-README.md')) {
        [IO.File]::Copy((Join-Path $repoRoot "portable\$file"), (Join-Path $portableRoot $file), $true)
    }
    foreach ($file in @('README.md', 'LICENSE', 'SECURITY.md')) {
        [IO.File]::Copy((Join-Path $repoRoot $file), (Join-Path $portableRoot $file), $true)
    }

    if (Test-Path -LiteralPath $portableZip) { Remove-Item -LiteralPath $portableZip -Force }
    Compress-Archive -Path $portableRoot -DestinationPath $portableZip -CompressionLevel Optimal

    $issPath = Join-Path $PSScriptRoot 'CodexThreeProviderSwitcher.iss'
    & $IsccPath "/DMyAppVersion=$Version" "/O$outputFullPath" $issPath
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed with exit code $LASTEXITCODE." }
    if (-not (Test-Path -LiteralPath $setupExe)) { throw "Installer was not created: $setupExe" }

    $artifacts = Get-Item -LiteralPath $setupExe, $portableZip
    $artifacts | ForEach-Object {
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        [pscustomobject]@{ File = $_.Name; Bytes = $_.Length; SHA256 = $hash }
    }
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) {
        $resolvedStaging = [IO.Path]::GetFullPath($stagingRoot)
        $resolvedTemp = [IO.Path]::GetFullPath($env:TEMP)
        if (-not $resolvedStaging.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove staging directory outside TEMP: $resolvedStaging"
        }
        Remove-Item -LiteralPath $resolvedStaging -Recurse -Force
    }
}
