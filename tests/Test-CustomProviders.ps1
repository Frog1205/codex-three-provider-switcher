$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $env:TEMP ('codex-custom-provider-test-' + [guid]::NewGuid().ToString('N'))
$previousAppData = $env:APPDATA
$previousTestKey = $env:CODEX_RELEASE_TEST_KEY
try {
    [IO.Directory]::CreateDirectory($testRoot) | Out-Null
    $env:APPDATA = $testRoot
    $env:CODEX_RELEASE_TEST_KEY = 'offline-test-placeholder'
    $config = Join-Path $testRoot 'config.toml'
    $initial = "model_provider = `"openai`"`r`nmodel = `"test-model`"`r`n`r`n[features]`r`nshell_tool = true`r`n`r`n[mcp_servers.fixture]`r`ncommand = `"fixture`"`r`n"
    [IO.File]::WriteAllText($config, $initial)
    . (Join-Path $repoRoot 'src\CodexProviderSwitcher.ps1') -Mode status -ConfigPath $config -NoRestart | Out-Null

    $route = [pscustomobject]@{
        id = 'release-fixture'; display_name = '中文测试线路'; provider_id = 'release-fixture'
        name = '中文测试线路'; base_url = 'http://127.0.0.1:1/v1'; env_key = 'CODEX_RELEASE_TEST_KEY'
        wire_api = 'responses'; model = 'offline-model'; reasoning_effort = 'medium'
        requires_openai_auth = $false; disable_response_storage = $true
    }
    Save-CustomProviders @($route)
    $registryText = [IO.File]::ReadAllText((Get-CustomProvidersPath))
    if (-not $registryText.TrimStart().StartsWith('[')) { throw 'A singleton registry must remain a JSON array.' }
    $loaded = @(Get-CustomProviders)
    if ($loaded.Count -ne 1 -or $loaded[0].display_name -ne $route.display_name) { throw 'Chinese route metadata did not round trip.' }
    if ([IO.File]::ReadAllText($config) -ne $initial) { throw 'Saving a route changed the active configuration.' }
    if ($registryText.Contains($env:CODEX_RELEASE_TEST_KEY)) { throw 'Registry contains a credential value.' }

    [void](Set-CodexProvider 'release-fixture' $false)
    $updated = [IO.File]::ReadAllText($config)
    if ($updated -notmatch 'model_provider = "release-fixture"' -or $updated -notmatch '\[model_providers.release-fixture\]') { throw 'Custom route switch failed.' }
    if ($updated -notmatch '\[features\]' -or $updated -notmatch '\[mcp_servers.fixture\]') { throw 'Unrelated configuration was lost.' }
    if ($updated.Contains($env:CODEX_RELEASE_TEST_KEY)) { throw 'Config contains a credential value.' }
    $backups = @(Get-ChildItem -LiteralPath (Join-Path $testRoot 'provider-switch-backups') -Filter '*.toml')
    if ($backups.Count -ne 1 -or [IO.File]::ReadAllText($backups[0].FullName) -ne $initial) { throw 'Original config backup is missing or incorrect.' }

    Save-CustomProviders @()
    if (@(Get-CustomProviders).Count -ne 0) { throw 'Empty registry failed.' }
    Write-Output 'PASS: custom registry JSON arrays, UTF-8 names, save without switch, custom routing, config preservation, credential isolation, and exact backup.'
}
finally {
    $env:APPDATA = $previousAppData
    $env:CODEX_RELEASE_TEST_KEY = $previousTestKey
    if (Test-Path -LiteralPath $testRoot) {
        $absolute = [IO.Path]::GetFullPath($testRoot)
        $tempPrefix = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
        if (-not $absolute.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe cleanup path.' }
        Remove-Item -LiteralPath $absolute -Recurse -Force
    }
}
