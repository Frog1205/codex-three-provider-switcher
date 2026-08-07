$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$script = Join-Path $repoRoot 'src\CodexProviderSwitcher.ps1'
$providers = Join-Path $repoRoot 'src\providers.json'
$testRoot = Join-Path $env:TEMP ('codex-provider-switcher-test-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null

try {
    $config = Join-Path $testRoot 'config.toml'
    $auth = Join-Path $testRoot 'auth.json'
    $initial = @'
model_provider = "openai"
model = "gpt-5.6-sol"
model_reasoning_effort = "medium"
personality = "pragmatic"

[features]
shell_tool = true

[mcp_servers.example]
command = "example"
'@
    [IO.File]::WriteAllText($config, $initial, (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText($auth, '{}', (New-Object Text.UTF8Encoding($false)))
    $env:HONKNET_API_KEY = 'test-only-honknet-placeholder'
    $env:DEEPSEEK_API_KEY = 'test-only-deepseek-placeholder'

    $expected = @(
        @{ Mode = 'gpt'; Provider = 'openai'; Model = 'gpt-5.6-sol' },
        @{ Mode = 'honkai'; Provider = 'honknet'; Model = 'gpt-5.6-sol' },
        @{ Mode = 'ds'; Provider = 'deepseek'; Model = 'deepseek-v4-flash' },
        @{ Mode = 'gpt'; Provider = 'openai'; Model = 'gpt-5.6-sol' }
    )

    foreach ($case in $expected) {
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script `
            -Mode $case.Mode -ConfigPath $config -ProvidersPath $providers -NoRestart
        if ($LASTEXITCODE -ne 0) { throw "Switch failed: $($case.Mode)" }
        $text = [IO.File]::ReadAllText($config)
        $provider = [regex]::Match($text, '(?m)^model_provider\s*=\s*"([^"]+)"').Groups[1].Value
        $model = [regex]::Match($text, '(?m)^model\s*=\s*"([^"]+)"').Groups[1].Value
        if ($provider -ne $case.Provider -or $model -ne $case.Model) {
            throw "Unexpected state for $($case.Mode): provider=$provider model=$model"
        }
        if ($text -notmatch '(?m)^personality\s*=\s*"pragmatic"\r?$') { throw 'Unrelated top-level setting was lost.' }
        if ($text -notmatch '(?m)^\[mcp_servers\.example\]\r?$') { throw 'MCP configuration was lost.' }
    }

    $backupCount = @(Get-ChildItem -LiteralPath (Join-Path $testRoot 'provider-switch-backups') -Filter '*.toml').Count
    if ($backupCount -ne 4) { throw "Expected 4 backups, found $backupCount" }
    Write-Output 'PASS: syntax, aliases, provider/model routing, unrelated config preservation, and backups.'
}
finally {
    $env:HONKNET_API_KEY = $null
    $env:DEEPSEEK_API_KEY = $null
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
