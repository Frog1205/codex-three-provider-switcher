$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$buildScript = Join-Path $repoRoot 'packaging\Build-MSIX.ps1'
$assetScript = Join-Path $repoRoot 'packaging\msix\Generate-MSIXAssets.ps1'
$launcherSource = Join-Path $repoRoot 'packaging\msix\CodexSwitcherLauncher.cs'
$manifestPath = Join-Path $repoRoot 'packaging\msix\AppxManifest.template.xml'
$tempRoot = Join-Path $env:TEMP ('codex-switcher-msix-test-' + [guid]::NewGuid().ToString('N'))

try {
    foreach ($script in @($buildScript, $assetScript)) {
        $tokens = $null
        $errors = $null
        [Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$errors) | Out-Null
        if ($errors.Count -gt 0) { throw "PowerShell syntax errors in $script" }
    }

    [xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
    $namespace = New-Object Xml.XmlNamespaceManager($manifest.NameTable)
    $namespace.AddNamespace('m', 'http://schemas.microsoft.com/appx/manifest/foundation/windows10')
    $namespace.AddNamespace('rescap', 'http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities')
    $apps = @($manifest.SelectNodes('/m:Package/m:Applications/m:Application', $namespace))
    if ($apps.Count -ne 2) { throw 'The manifest must define the switcher and key configurator applications.' }
    if ($null -eq $manifest.SelectSingleNode('/m:Package/m:Capabilities/rescap:Capability[@Name="runFullTrust"]', $namespace)) {
        throw 'The manifest must declare runFullTrust.'
    }
    if ([string]$manifest.Package.Identity.Name -ne 'STORE_IDENTITY_NAME') {
        throw 'The manifest identity must remain an explicit Partner Center placeholder.'
    }

    [IO.Directory]::CreateDirectory($tempRoot) | Out-Null
    & $assetScript -OutputDir (Join-Path $tempRoot 'Assets')
    Add-Type -AssemblyName System.Drawing
    foreach ($asset in @(
        @{ Name = 'StoreLogo.png'; Width = 50; Height = 50 },
        @{ Name = 'Square44x44Logo.png'; Width = 44; Height = 44 },
        @{ Name = 'Square150x150Logo.png'; Width = 150; Height = 150 },
        @{ Name = 'Wide310x150Logo.png'; Width = 310; Height = 150 }
    )) {
        $image = [Drawing.Image]::FromFile((Join-Path $tempRoot "Assets\$($asset.Name)"))
        try {
            if ($image.Width -ne $asset.Width -or $image.Height -ne $asset.Height) {
                throw "Unexpected dimensions for $($asset.Name)."
            }
        }
        finally { $image.Dispose() }
    }

    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path -LiteralPath $csc)) { throw 'The 64-bit .NET Framework compiler is missing.' }
    & $csc /nologo /target:winexe /platform:x64 "/out:$(Join-Path $tempRoot 'CodexSwitcherLauncher.exe')" $launcherSource
    if ($LASTEXITCODE -ne 0) { throw 'The MSIX launcher did not compile.' }
    & $csc /nologo /target:winexe /platform:x64 /define:CONFIGURE_KEYS "/out:$(Join-Path $tempRoot 'CodexKeyConfigurator.exe')" $launcherSource
    if ($LASTEXITCODE -ne 0) { throw 'The MSIX key configurator did not compile.' }

    Write-Output 'PASS: MSIX manifest, runFullTrust declaration, deterministic assets, and x64 launchers.'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        $resolvedTempRoot = [IO.Path]::GetFullPath($tempRoot)
        $resolvedTemp = [IO.Path]::GetFullPath($env:TEMP)
        if (-not $resolvedTempRoot.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove test directory outside TEMP: $resolvedTempRoot"
        }
        Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force
    }
}
