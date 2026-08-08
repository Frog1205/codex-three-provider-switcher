param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9.-]+$')]
    [string]$IdentityName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Publisher,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$PublisherDisplayName,

    [ValidatePattern('^\d+\.\d+\.\d+(?:\.0)?$')]
    [string]$Version = '1.0.0',

    [string]$DisplayName = 'Codex Three-Provider Switcher',

    [string]$OutputDir,

    [string]$WindowsSdkBinPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$msixSource = Join-Path $PSScriptRoot 'msix'
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $repoRoot 'dist'
}
$outputFullPath = [IO.Path]::GetFullPath($OutputDir)
$packageVersion = if ($Version -match '^\d+\.\d+\.\d+$') { "$Version.0" } else { $Version }

$versionParts = @($packageVersion.Split('.') | ForEach-Object { [int]$_ })
if ($versionParts[0] -eq 0) {
    throw 'The first MSIX version component cannot be 0.'
}
if ($versionParts | Where-Object { $_ -gt 65535 }) {
    throw 'Each MSIX version component must be between 0 and 65535.'
}

function Find-WindowsSdkTool {
    param([string]$Name)

    if (-not [string]::IsNullOrWhiteSpace($WindowsSdkBinPath)) {
        foreach ($candidate in @(
            (Join-Path $WindowsSdkBinPath $Name),
            (Join-Path $WindowsSdkBinPath "x64\$Name")
        )) {
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
        throw "$Name was not found under WindowsSdkBinPath: $WindowsSdkBinPath"
    }

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }

    $kitsRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    $candidate = Get-ChildItem -LiteralPath $kitsRoot -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName "x64\$Name" } |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
    if ($candidate) { return $candidate }

    throw "$Name was not found. Install the Windows 10/11 SDK before building the MSIX."
}

$makeAppx = Find-WindowsSdkTool 'MakeAppx.exe'
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $csc)) {
    throw 'The 64-bit .NET Framework C# compiler was not found.'
}

[IO.Directory]::CreateDirectory($outputFullPath) | Out-Null
$stagingRoot = Join-Path $env:TEMP ('codex-switcher-msix-' + [guid]::NewGuid().ToString('N'))
$packageRoot = Join-Path $stagingRoot 'package'
$manifestPath = Join-Path $packageRoot 'AppxManifest.xml'
$packagePath = Join-Path $outputFullPath "Codex-Three-Provider-Switcher-$packageVersion-x64-Store.msix"

try {
    [IO.Directory]::CreateDirectory($packageRoot) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $packageRoot 'Assets')) | Out-Null

    $launcherSource = Join-Path $msixSource 'CodexSwitcherLauncher.cs'
    & $csc /nologo /target:winexe /platform:x64 /optimize+ "/out:$(Join-Path $packageRoot 'CodexSwitcherLauncher.exe')" $launcherSource
    if ($LASTEXITCODE -ne 0) { throw "C# compiler failed with exit code $LASTEXITCODE." }
    & $csc /nologo /target:winexe /platform:x64 /optimize+ /define:CONFIGURE_KEYS "/out:$(Join-Path $packageRoot 'CodexKeyConfigurator.exe')" $launcherSource
    if ($LASTEXITCODE -ne 0) { throw "C# compiler failed with exit code $LASTEXITCODE." }

    foreach ($file in @('CodexProviderSwitcher.ps1', 'Get-CodexRateLimits.ps1', 'ConfigureProviderKeys.ps1', 'providers.json', 'deepseek-model-catalog.json')) {
        [IO.File]::Copy((Join-Path $repoRoot "src\$file"), (Join-Path $packageRoot $file), $true)
    }
    foreach ($file in @('README.md', 'LICENSE', 'SECURITY.md')) {
        [IO.File]::Copy((Join-Path $repoRoot $file), (Join-Path $packageRoot $file), $true)
    }

    & (Join-Path $msixSource 'Generate-MSIXAssets.ps1') -OutputDir (Join-Path $packageRoot 'Assets')

    [xml]$manifest = Get-Content -LiteralPath (Join-Path $msixSource 'AppxManifest.template.xml') -Raw -Encoding UTF8
    $namespace = New-Object Xml.XmlNamespaceManager($manifest.NameTable)
    $namespace.AddNamespace('m', 'http://schemas.microsoft.com/appx/manifest/foundation/windows10')
    $namespace.AddNamespace('uap', 'http://schemas.microsoft.com/appx/manifest/uap/windows10')

    $identity = $manifest.SelectSingleNode('/m:Package/m:Identity', $namespace)
    $identity.SetAttribute('Name', $IdentityName)
    $identity.SetAttribute('Publisher', $Publisher)
    $identity.SetAttribute('Version', $packageVersion)

    $manifest.SelectSingleNode('/m:Package/m:Properties/m:DisplayName', $namespace).InnerText = $DisplayName
    $manifest.SelectSingleNode('/m:Package/m:Properties/m:PublisherDisplayName', $namespace).InnerText = $PublisherDisplayName
    $mainVisuals = $manifest.SelectSingleNode('/m:Package/m:Applications/m:Application[@Id="Switcher"]/uap:VisualElements', $namespace)
    $mainVisuals.SetAttribute('DisplayName', $DisplayName)

    $settings = New-Object Xml.XmlWriterSettings
    $settings.Encoding = New-Object Text.UTF8Encoding($false)
    $settings.Indent = $true
    $writer = [Xml.XmlWriter]::Create($manifestPath, $settings)
    try { $manifest.Save($writer) } finally { $writer.Dispose() }

    if (Test-Path -LiteralPath $packagePath) { Remove-Item -LiteralPath $packagePath -Force }
    & $makeAppx pack /d $packageRoot /p $packagePath /o
    if ($LASTEXITCODE -ne 0) { throw "MakeAppx failed with exit code $LASTEXITCODE." }

    $package = Get-Item -LiteralPath $packagePath
    [pscustomobject]@{
        File = $package.Name
        Bytes = $package.Length
        SHA256 = (Get-FileHash -LiteralPath $package.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        Signed = $false
        Purpose = 'Upload to Microsoft Store Partner Center; not for sideload installation'
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
