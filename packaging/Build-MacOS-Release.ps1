param(
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version = '1.3.0',
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$ArtifactSuffix = 'V_1.3_260829.02',
    [string]$OutputDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist')
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$outputFullPath = [IO.Path]::GetFullPath($OutputDir)
[IO.Directory]::CreateDirectory($outputFullPath) | Out-Null
$tag = if ([string]::IsNullOrWhiteSpace($ArtifactSuffix)) { '' } else { "-$ArtifactSuffix" }
$packageName = "Codex-Three-Provider-Switcher-macOS-AppleSilicon$tag"
$archivePath = Join-Path $outputFullPath "$packageName.zip"
$stagingRoot = Join-Path $env:TEMP ('codex-switcher-macos-' + [guid]::NewGuid().ToString('N'))
$packageRoot = Join-Path $stagingRoot $packageName

try {
    [IO.Directory]::CreateDirectory((Join-Path $packageRoot 'macos')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $packageRoot 'src')) | Out-Null
    foreach ($file in @('TokenModelSwitch.py', 'Start-Token-Model-Switch.command', 'README.md')) {
        [IO.File]::Copy((Join-Path $repoRoot "macos\$file"), (Join-Path $packageRoot "macos\$file"), $true)
    }
    foreach ($file in @('providers.json', 'deepseek-model-catalog.json')) {
        [IO.File]::Copy((Join-Path $repoRoot "src\$file"), (Join-Path $packageRoot "src\$file"), $true)
    }
    foreach ($file in @('README.md', 'LICENSE')) {
        [IO.File]::Copy((Join-Path $repoRoot $file), (Join-Path $packageRoot $file), $true)
    }
    if (Test-Path -LiteralPath $archivePath) { Remove-Item -LiteralPath $archivePath -Force }
    Compress-Archive -Path $packageRoot -DestinationPath $archivePath -CompressionLevel Optimal
    $hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    [pscustomobject]@{ File = (Split-Path -Leaf $archivePath); Bytes = (Get-Item $archivePath).Length; SHA256 = $hash }
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
