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

    foreach ($case in @(
        @{ Base='https://example.invalid/v1'; Wire='responses'; Expected='https://example.invalid/v1/responses' },
        @{ Base='https://example.invalid/custom/api/v2/'; Wire='chat_completions'; Expected='https://example.invalid/custom/api/v2/chat/completions' },
        @{ Base='http://127.0.0.1:8000/'; Wire='responses'; Expected='http://127.0.0.1:8000/responses' }
    )) {
        if ((Get-CustomProviderEndpoint $case.Base $case.Wire) -ne $case.Expected) { throw 'Base URL path preservation or suffix selection failed.' }
    }
    foreach ($invalidBase in @('example.invalid/v1', 'ftp://example.invalid/v1', 'https://example.invalid/v1/responses', 'https://example.invalid/v1/chat/completions/', 'https://example.invalid/v1?key=fixture', 'https://example.invalid/v1#fragment', 'https://user:fixture@example.invalid/v1')) {
        $rejected = $false
        try { Get-CustomProviderEndpoint $invalidBase 'responses' | Out-Null } catch { $rejected=$true }
        if (-not $rejected) { throw 'An invalid, credential-bearing or complete endpoint was accepted as a base URL.' }
    }

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

    $both = Resolve-CustomProviderCredential -Id 'both-fixture' -EnvironmentName 'CODEX_RELEASE_TEST_KEY' -ApiKey 'ignored-direct-fixture'
    if ($both.Source -ne 'environment' -or $both.ApiKey -ne $env:CODEX_RELEASE_TEST_KEY -or $both.WriteKey) { throw 'Environment variable did not take precedence.' }
    $missingName = 'CODEX_TEST_MISSING_' + [guid]::NewGuid().ToString('N')
    $missingRejected = $false
    try { Resolve-CustomProviderCredential -Id 'missing-fixture' -EnvironmentName $missingName -ApiKey 'must-not-fallback' | Out-Null }
    catch { $missingRejected = $_.Exception.Message.Contains($missingName) }
    if (-not $missingRejected) { throw 'A named but missing environment variable must not fall back to a direct key.' }
    $emptyRejected = $false
    try { Resolve-CustomProviderCredential -Id 'empty-fixture' -EnvironmentName '' -ApiKey '' | Out-Null }
    catch { $emptyRejected = $true }
    if (-not $emptyRejected) { throw 'Missing both credentials should be rejected.' }

    # Mock only persistent key writes; the production resolver/route serialization/config writer run unchanged.
    $script:keyWrites = 0
    function Set-CustomProviderKey {
        param([string]$Name, [string]$Value)
        $script:keyWrites++
        [Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
    }
    $environmentRoute = Save-CustomProviderRoute -Name '变量线路' -Id 'environment-fixture' -BaseUrl 'http://127.0.0.1:1/v1' -Model 'vendor/real-model:2026-01' -EnvironmentName 'CODEX_RELEASE_TEST_KEY' -ApiKey 'ignored-direct-fixture' -WireApi 'responses'
    if ($script:keyWrites -ne 0 -or $env:CODEX_RELEASE_TEST_KEY -ne 'offline-test-placeholder') { throw 'Named environment value was overwritten by the ignored direct key.' }
    $directId = 'direct-' + [guid]::NewGuid().ToString('N').Substring(0,8)
    $direct = Save-CustomProviderRoute -Name '直接填写密钥' -Id $directId -BaseUrl 'http://127.0.0.1:1/v1' -Model 'vendor/real-model:2026-01' -EnvironmentName '' -ApiKey 'direct-only-fixture' -WireApi 'responses'
    if ($script:keyWrites -ne 1 -or $direct.credential_source -ne 'api_key' -or -not $direct.env_key) { throw 'Direct-key save failed.' }
    if ((Get-CustomProviderKeyName 'a-b') -eq (Get-CustomProviderKeyName 'a_b')) { throw 'Distinct route IDs collided in generated key names.' }
    $reloaded = @(Get-CustomProviders | Where-Object { $_.id -eq $directId })[0]
    $reused = Resolve-CustomProviderCredential -Id $directId -EnvironmentName '' -ApiKey '' -SavedDefinition $reloaded
    if ($reused.ApiKey -ne 'direct-only-fixture' -or $reused.WriteKey) { throw 'Saved direct key was not reusable without re-entry.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'src\CodexProviderSwitcher.ps1') -Mode $directId -ConfigPath $config -NoRestart | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Direct-key route failed to switch in a fresh process.' }
    $directConfig = [IO.File]::ReadAllText($config)
    if (-not $directConfig.Contains('model = "vendor/real-model:2026-01"')) { throw 'Real model ID was changed.' }
    foreach ($secretFixture in @('direct-only-fixture','ignored-direct-fixture','offline-test-placeholder')) {
        if ($directConfig.Contains($secretFixture) -or [IO.File]::ReadAllText((Get-CustomProvidersPath)).Contains($secretFixture)) { throw 'A credential value leaked into config or route metadata.' }
    }
    [Environment]::SetEnvironmentVariable($direct.env_key, $null, 'Process')

    Save-CustomProviders @()
    if (@(Get-CustomProviders).Count -ne 0) { throw 'Empty registry failed.' }
    Write-Output 'PASS: custom registry, exact model IDs, environment-first credentials, no missing-variable fallback, direct-key save/reload/fresh-process switch, credential isolation, and exact backup.'
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
