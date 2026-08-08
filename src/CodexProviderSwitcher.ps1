param(
    [ValidateSet('gui', 'official', 'gpt', 'honkai', 'honknet', 'deepseek', 'ds', 'status')]
    [string]$Mode = 'gui',
    [string]$ConfigPath = (Join-Path $env:USERPROFILE '.codex\config.toml'),
    [string]$ProvidersPath = (Join-Path $PSScriptRoot 'providers.json'),
    [string]$RateLimitsPath = (Join-Path $PSScriptRoot 'Get-CodexRateLimits.ps1'),
    [ValidateRange(15, 3600)]
    [int]$QuotaRefreshSeconds = 60,
    [ValidateSet('zh-CN', 'en')]
    [string]$Language = 'zh-CN',
    [switch]$NoRestart
)

$ErrorActionPreference = 'Stop'
$AppId = 'OpenAI.Codex_2p2nqsd0c76g0!App'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Get-Providers {
    if (-not (Test-Path -LiteralPath $ProvidersPath)) {
        throw "Provider definitions not found: $ProvidersPath"
    }
    try {
        return Get-Content -Raw -LiteralPath $ProvidersPath | ConvertFrom-Json
    }
    catch {
        throw "Provider definitions are invalid JSON: $ProvidersPath"
    }
}

function Get-Definition {
    param([ValidateSet('official', 'honknet', 'deepseek')][string]$Provider)

    $definitions = Get-Providers
    $definition = $definitions.$Provider
    if ($null -eq $definition) { throw "Provider definition is missing: $Provider" }
    return $definition
}

function Get-TopLevelValue {
    param([string]$Text, [string]$Key)

    $firstTable = [regex]::Match($Text, '(?m)^[ \t]*\[')
    $head = if ($firstTable.Success) { $Text.Substring(0, $firstTable.Index) } else { $Text }
    $match = [regex]::Match($head, "(?m)^[ \t]*$([regex]::Escape($Key))[ \t]*=[ \t]*[`"']([^`"']+)[`"'][ \t]*$")
    if ($match.Success) { return $match.Groups[1].Value }
    return $null
}

function Get-KeyPresent {
    param([string]$Name)

    foreach ($scope in @('Process', 'User', 'Machine')) {
        if (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($Name, $scope))) {
            return $true
        }
    }
    return $false
}

function Get-CatalogPath {
    param([object]$Definition)

    if ([string]::IsNullOrWhiteSpace([string]$Definition.catalog_file)) { return $null }
    return Join-Path (Split-Path -Parent $ProvidersPath) ([string]$Definition.catalog_file)
}

function Test-Catalog {
    param([object]$Definition)

    $catalogPath = Get-CatalogPath $Definition
    if ($null -eq $catalogPath) { return $true }
    if (-not (Test-Path -LiteralPath $catalogPath)) { return $false }
    try {
        $catalog = Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json
        return @($catalog.models | Where-Object { $_.slug -eq $Definition.model }).Count -gt 0
    }
    catch { return $false }
}

function Get-CurrentState {
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        return [pscustomobject]@{ Provider = 'unknown'; Model = 'unknown'; Display = 'Unknown' }
    }
    $text = [IO.File]::ReadAllText($ConfigPath)
    $provider = Get-TopLevelValue $text 'model_provider'
    if ([string]::IsNullOrWhiteSpace($provider)) { $provider = 'openai' }
    $model = Get-TopLevelValue $text 'model'
    $definitions = Get-Providers
    $display = switch ($provider.ToLowerInvariant()) {
        'openai' { [string]$definitions.official.display_name }
        'honknet' { [string]$definitions.honknet.display_name }
        'deepseek' { [string]$definitions.deepseek.display_name }
        'custom' {
            $customBlock = [regex]::Match(
                $text,
                '(?ms)^[ \t]*\[model_providers\.custom\][ \t]*\r?\n.*?(?=^[ \t]*\[|\z)'
            ).Value
            if ($customBlock -match '(?im)^[ \t]*base_url[ \t]*=[ \t]*["''][^"'']*honknet[^"'']*["'']') {
                "$($definitions.honknet.display_name) (legacy)"
            }
            else { 'custom' }
        }
        default { $provider }
    }
    return [pscustomobject]@{ Provider = $provider; Model = $model; Display = $display }
}

function ConvertTo-TomlString {
    param([string]$Value)
    return '"' + $Value.Replace('\', '\\').Replace('"', '\"') + '"'
}

function New-ProviderBlock {
    param([object]$Definition)

    $id = [string]$Definition.provider_id
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("[model_providers.$id]")
    foreach ($key in @('name', 'base_url', 'env_key', 'wire_api')) {
        $value = [string]$Definition.$key
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $lines.Add("$key = $(ConvertTo-TomlString $value)")
        }
    }
    $lines.Add("requires_openai_auth = $(([bool]$Definition.requires_openai_auth).ToString().ToLowerInvariant())")
    foreach ($key in @('request_max_retries', 'stream_max_retries', 'stream_idle_timeout_ms')) {
        if ($null -ne $Definition.$key) { $lines.Add("$key = $($Definition.$key)") }
    }
    return $lines -join "`r`n"
}

function New-SwitchedConfig {
    param([ValidateSet('official', 'honknet', 'deepseek')][string]$Provider)

    if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
    $definition = Get-Definition $Provider
    if ([bool]$definition.requires_openai_auth) {
        $authPath = Join-Path (Split-Path -Parent $ConfigPath) 'auth.json'
        if (-not (Test-Path -LiteralPath $authPath)) {
            throw 'Official OpenAI login was not found. Sign in to Codex first.'
        }
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$definition.env_key)) {
        if (-not (Get-KeyPresent ([string]$definition.env_key))) {
            throw "$($definition.env_key) is missing. Run Install.ps1 or configure the Windows user environment variable."
        }
    }
    if (-not (Test-Catalog $definition)) {
        throw "The model catalog is missing or does not contain $($definition.model): $(Get-CatalogPath $definition)"
    }

    $text = [IO.File]::ReadAllText($ConfigPath)
    $firstTable = [regex]::Match($text, '(?m)^[ \t]*\[')
    if ($firstTable.Success) {
        $head = $text.Substring(0, $firstTable.Index)
        $tail = $text.Substring($firstTable.Index)
    }
    else {
        $head = $text
        $tail = ''
    }

    $switchKeys = 'model|model_provider|model_catalog_json|model_reasoning_effort|disable_response_storage'
    $head = [regex]::Replace($head, "(?m)^[ \t]*(?:$switchKeys)[ \t]*=.*(?:\r?\n|$)", '')

    $settings = New-Object System.Collections.Generic.List[string]
    $settings.Add("model_provider = $(ConvertTo-TomlString ([string]$definition.provider_id))")
    $settings.Add("model = $(ConvertTo-TomlString ([string]$definition.model))")
    $settings.Add("model_reasoning_effort = $(ConvertTo-TomlString ([string]$definition.reasoning_effort))")
    if ([bool]$definition.disable_response_storage) { $settings.Add('disable_response_storage = true') }
    $catalogPath = Get-CatalogPath $definition
    if ($null -ne $catalogPath) {
        $escapedCatalog = $catalogPath.Replace("'", "''")
        $settings.Add("model_catalog_json = '$escapedCatalog'")
    }

    if ($definition.provider_id -ne 'openai') {
        $providerId = [regex]::Escape([string]$definition.provider_id)
        $blockPattern = "(?ms)^[ \t]*\[model_providers\.$providerId\][ \t]*\r?\n.*?(?=^[ \t]*\[|\z)"
        $tail = [regex]::Replace($tail, $blockPattern, '').TrimEnd()
        $tail += "`r`n`r`n" + (New-ProviderBlock $definition) + "`r`n"
    }

    $parts = @(($settings -join "`r`n").Trim(), $head.Trim(), $tail.Trim()) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    return ($parts -join "`r`n`r`n") + "`r`n"
}

function Get-CodexDesktopProcesses {
    return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -eq 'ChatGPT.exe' -and [string]$_.ExecutablePath -match '\\OpenAI\.Codex_'
    })
}

function Test-RunningInsideCodex {
    $processId = $PID
    for ($i = 0; $i -lt 12 -and $processId -gt 0; $i++) {
        $process = Get-CimInstance Win32_Process -Filter "ProcessId = $processId" -ErrorAction SilentlyContinue
        if ($null -eq $process) { break }
        if ($processId -ne $PID -and ($process.Name -eq 'codex.exe' -or $process.Name -eq 'ChatGPT.exe')) {
            return $true
        }
        $processId = [int]$process.ParentProcessId
    }
    return $false
}

function Stop-CodexDesktop {
    $processes = Get-CodexDesktopProcesses
    foreach ($item in @($processes | Where-Object { [string]$_.CommandLine -notmatch '--type=' })) {
        $process = Get-Process -Id $item.ProcessId -ErrorAction SilentlyContinue
        if ($null -ne $process) { [void]$process.CloseMainWindow() }
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    do {
        Start-Sleep -Milliseconds 200
        $remaining = Get-CodexDesktopProcesses
    } while ($remaining.Count -gt 0 -and [DateTime]::UtcNow -lt $deadline)
    foreach ($item in $remaining) { Stop-Process -Id $item.ProcessId -Force -ErrorAction SilentlyContinue }
}

function Start-CodexDesktop {
    Start-Process -FilePath 'explorer.exe' -ArgumentList "shell:AppsFolder\$AppId"
}

function Write-ConfigAtomically {
    param([string]$Content)

    $configDir = Split-Path -Parent $ConfigPath
    $backupDir = Join-Path $configDir 'provider-switch-backups'
    [IO.Directory]::CreateDirectory($backupDir) | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $backupPath = Join-Path $backupDir "config-$stamp.toml"
    [IO.File]::Copy($ConfigPath, $backupPath, $false)
    $tempPath = Join-Path $configDir ('.config-switch-' + [guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::WriteAllText($tempPath, $Content, $Utf8NoBom)
    try {
        [IO.File]::Replace($tempPath, $ConfigPath, $null)
    }
    catch {
        [IO.File]::Copy($tempPath, $ConfigPath, $true)
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }
    return $backupPath
}

function Set-CodexProvider {
    param(
        [ValidateSet('official', 'honknet', 'deepseek')][string]$Provider,
        [bool]$Interactive
    )

    $definition = Get-Definition $Provider
    if ($Interactive) {
        Add-Type -AssemblyName System.Windows.Forms
        $answer = [Windows.Forms.MessageBox]::Show(
            "Switch to $($definition.display_name)?`r`n`r`nSave the current task first. Create a new task after restart.",
            'Confirm provider switch',
            [Windows.Forms.MessageBoxButtons]::OKCancel,
            [Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($answer -ne [Windows.Forms.DialogResult]::OK) { return $false }
    }

    $newConfig = New-SwitchedConfig $Provider
    $canRestart = -not $NoRestart -and -not (Test-RunningInsideCodex)
    if ($canRestart) { Stop-CodexDesktop }
    try { $backupPath = Write-ConfigAtomically $newConfig }
    catch {
        if ($canRestart) { Start-CodexDesktop }
        throw
    }
    if ($canRestart) { Start-CodexDesktop }
    Write-Output "SWITCH_OK provider=$Provider backup=$backupPath config=$ConfigPath"
    if (-not $NoRestart -and -not $canRestart) {
        Write-Warning 'Config changed, but Codex was not restarted because the switcher is running inside Codex. Restart the desktop app manually.'
    }
    return $true
}

function Show-Switcher {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [Windows.Forms.Application]::EnableVisualStyles()

    $definitions = Get-Providers
    $uiState = @{ Language = $Language }
    $strings = @{
        'zh-CN' = @{
            FormTitle = 'Codex 三线路切换器'
            Title = 'Codex 线路切换器'
            LanguageButton = 'English'
            CurrentStatus = '当前线路：{0}    模型：{1}'
            Hint = "切换前请保存当前任务。`r`nCodex 重启后请新建任务。"
            OfficialButton = 'GPT 官方'
            HonknetButton = 'Honknet'
            DeepSeekButton = 'DeepSeek'
            LegacySuffix = '（旧配置）'
            Health = 'Honknet 密钥：{0}    DeepSeek 密钥：{1}    模型目录：{2}'
            Ready = '已配置'
            Missing = '未配置'
            CatalogReady = '可用'
            CatalogMissing = '缺失'
            ConfirmTitle = '确认切换线路'
            ConfirmMessage = "确定切换到 {0} 吗？`r`n`r`n请先保存当前任务，重启后新建任务。"
            SwitchDoneTitle = '切换完成'
            SwitchDone = '线路已切换。请在 Codex 中新建任务。'
            SwitchFailedTitle = '切换失败'
            FriendlyLoginMissing = '未检测到 OpenAI 官方登录。请先登录 Codex。'
            FriendlyKeyMissing = '所选线路的 Windows 用户环境变量未配置，请重新运行安装程序或手动配置。'
            FriendlyCatalogMissing = '所选模型的模型目录缺失或配置不正确。'
            FriendlyConfigMissing = '未找到 Codex 配置文件，请先启动并登录一次 Codex。'
            FriendlyFailure = '切换失败：{0}'
            QuotaTitle = '官方 Codex 额度'
            Refresh = '刷新'
            Checking = '检测中...'
            QuotaChecking = '官方 Codex 剩余量：检测中...'
            QuotaRemaining = '官方 Codex 剩余量：{0:0.#}%'
            QuotaUnavailable = '官方 Codex 剩余量：暂不可用'
            ResetWaiting = '重置时间：等待官方账号数据'
            ResetAt = '重置时间：{0}'
            ResetUnknown = '重置时间：未知'
            ResetNotReported = '重置时间：官方未返回'
            AutoRefresh = '自动刷新：每 {0} 秒'
            RelayAvailable = "官方额度已恢复，可以切回 GPT 官方。`r`n更新时间 {0}；每 {1} 秒自动刷新。"
            QuotaExhausted = "官方额度已用完，可继续使用中转线路等待重置。`r`n更新时间 {0}；每 {1} 秒自动刷新。"
            QuotaAvailable = "官方额度可用。`r`n更新时间 {0}；每 {1} 秒自动刷新。"
            ErrorReaderMissing = '未找到额度读取器，请重新安装本工具。'
            ErrorParseFailed = '无法解析官方额度数据。'
            ErrorTimedOut = '官方额度查询超时。'
            ErrorCheckFailed = '官方额度查询失败，请稍后重试。'
            ErrorStatus = "{0}`r`n线路切换功能仍可正常使用。"
            Privacy = '密钥仅从 Windows 环境变量读取；切换前会自动备份配置。'
        }
        'en' = @{
            FormTitle = 'Codex Three-Provider Switcher'
            Title = 'Codex Provider Switcher'
            LanguageButton = '中文'
            CurrentStatus = 'Current provider: {0}    Model: {1}'
            Hint = "Save the current task before switching.`r`nCreate a new task after Codex restarts."
            OfficialButton = 'GPT Official'
            HonknetButton = 'Honknet'
            DeepSeekButton = 'DeepSeek'
            LegacySuffix = ' (legacy)'
            Health = 'Honknet Key: {0}    DeepSeek Key: {1}    Catalog: {2}'
            Ready = 'Ready'
            Missing = 'Missing'
            CatalogReady = 'Ready'
            CatalogMissing = 'Missing'
            ConfirmTitle = 'Confirm provider switch'
            ConfirmMessage = "Switch to {0}?`r`n`r`nSave the current task first. Create a new task after restart."
            SwitchDoneTitle = 'Done'
            SwitchDone = 'Switch complete. Create a new task in Codex.'
            SwitchFailedTitle = 'Switch failed'
            FriendlyLoginMissing = 'Official OpenAI login was not found. Sign in to Codex first.'
            FriendlyKeyMissing = 'The Windows user environment variable for this provider is missing. Run the installer or configure it manually.'
            FriendlyCatalogMissing = 'The model catalog for the selected model is missing or invalid.'
            FriendlyConfigMissing = 'The Codex config file was not found. Start and sign in to Codex first.'
            FriendlyFailure = 'Switch failed: {0}'
            QuotaTitle = 'Official Codex quota'
            Refresh = 'Refresh'
            Checking = 'Checking...'
            QuotaChecking = 'Official Codex remaining: Checking...'
            QuotaRemaining = 'Official Codex remaining: {0:0.#}%'
            QuotaUnavailable = 'Official Codex remaining: Unavailable'
            ResetWaiting = 'Resets: Waiting for official account data'
            ResetAt = 'Resets: {0}'
            ResetUnknown = 'Resets: Unknown'
            ResetNotReported = 'Resets: Not reported'
            AutoRefresh = 'Auto refresh: every {0} seconds'
            RelayAvailable = "Official quota is available. You can switch back to GPT Official.`r`nUpdated {0}; auto refresh every {1} seconds."
            QuotaExhausted = "Official quota is exhausted. Keep using a relay until reset.`r`nUpdated {0}; auto refresh every {1} seconds."
            QuotaAvailable = "Official quota is available.`r`nUpdated {0}; auto refresh every {1} seconds."
            ErrorReaderMissing = 'Quota reader was not found. Reinstall this tool.'
            ErrorParseFailed = 'The official quota response could not be parsed.'
            ErrorTimedOut = 'Official quota check timed out.'
            ErrorCheckFailed = 'Official quota check failed. Try again later.'
            ErrorStatus = "{0}`r`nThe provider switcher remains available."
            Privacy = 'Keys come only from Windows environment variables. Config is backed up.'
        }
    }
    $text = { param([string]$Key) [string]$strings[$uiState.Language][$Key] }

    $form = New-Object Windows.Forms.Form
    $form.ClientSize = New-Object Drawing.Size(680, 500)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.Font = New-Object Drawing.Font('Microsoft YaHei UI', 10)

    $title = New-Object Windows.Forms.Label
    $title.Font = New-Object Drawing.Font('Microsoft YaHei UI', 19, [Drawing.FontStyle]::Bold)
    $title.AutoSize = $true
    $title.Location = New-Object Drawing.Point(30, 24)
    $form.Controls.Add($title)

    $languageButton = New-Object Windows.Forms.Button
    $languageButton.Size = New-Object Drawing.Size(88, 32)
    $languageButton.Location = New-Object Drawing.Point(559, 24)
    $form.Controls.Add($languageButton)

    $status = New-Object Windows.Forms.Label
    $status.AutoSize = $true
    $status.Location = New-Object Drawing.Point(33, 78)
    $form.Controls.Add($status)

    $hint = New-Object Windows.Forms.Label
    $hint.Size = New-Object Drawing.Size(610, 44)
    $hint.Location = New-Object Drawing.Point(33, 112)
    $form.Controls.Add($hint)

    $buttonSpecs = @(
        @{ TextKey = 'OfficialButton'; Provider = 'official'; X = 33; Color = [Drawing.Color]::FromArgb(16, 163, 127) },
        @{ TextKey = 'HonknetButton'; Provider = 'honknet'; X = 251; Color = [Drawing.Color]::FromArgb(37, 99, 235) },
        @{ TextKey = 'DeepSeekButton'; Provider = 'deepseek'; X = 469; Color = [Drawing.Color]::FromArgb(109, 40, 217) }
    )

    $providerButtons = @{}

    foreach ($spec in $buttonSpecs) {
        $button = New-Object Windows.Forms.Button
        $button.Tag = $spec.Provider
        $button.Size = New-Object Drawing.Size(178, 62)
        $button.Location = New-Object Drawing.Point($spec.X, 160)
        $button.BackColor = $spec.Color
        $button.ForeColor = [Drawing.Color]::White
        $button.FlatStyle = 'Flat'
        $form.Controls.Add($button)
        $providerButtons[$spec.Provider] = $button
    }

    $health = New-Object Windows.Forms.Label
    $health.AutoSize = $false
    $health.Size = New-Object Drawing.Size(610, 38)
    $health.Location = New-Object Drawing.Point(33, 244)
    $form.Controls.Add($health)

    $quotaTitle = New-Object Windows.Forms.Label
    $quotaTitle.Font = New-Object Drawing.Font('Microsoft YaHei UI', 12, [Drawing.FontStyle]::Bold)
    $quotaTitle.AutoSize = $true
    $quotaTitle.Location = New-Object Drawing.Point(33, 286)
    $form.Controls.Add($quotaTitle)

    $refreshQuotaButton = New-Object Windows.Forms.Button
    $refreshQuotaButton.Size = New-Object Drawing.Size(88, 32)
    $refreshQuotaButton.Location = New-Object Drawing.Point(559, 280)
    $form.Controls.Add($refreshQuotaButton)

    $quotaPercent = New-Object Windows.Forms.Label
    $quotaPercent.AutoSize = $true
    $quotaPercent.Font = New-Object Drawing.Font('Microsoft YaHei UI', 11, [Drawing.FontStyle]::Bold)
    $quotaPercent.Location = New-Object Drawing.Point(33, 322)
    $form.Controls.Add($quotaPercent)

    $quotaTrack = New-Object Windows.Forms.Panel
    $quotaTrack.Size = New-Object Drawing.Size(614, 20)
    $quotaTrack.Location = New-Object Drawing.Point(33, 351)
    $quotaTrack.BackColor = [Drawing.Color]::FromArgb(225, 228, 232)
    $form.Controls.Add($quotaTrack)

    $quotaFill = New-Object Windows.Forms.Panel
    $quotaFill.Size = New-Object Drawing.Size(1, 20)
    $quotaFill.Location = New-Object Drawing.Point(0, 0)
    $quotaFill.BackColor = [Drawing.Color]::FromArgb(156, 163, 175)
    $quotaTrack.Controls.Add($quotaFill)

    $quotaReset = New-Object Windows.Forms.Label
    $quotaReset.AutoSize = $true
    $quotaReset.Location = New-Object Drawing.Point(33, 382)
    $form.Controls.Add($quotaReset)

    $quotaStatus = New-Object Windows.Forms.Label
    $quotaStatus.AutoSize = $false
    $quotaStatus.Size = New-Object Drawing.Size(614, 34)
    $quotaStatus.Location = New-Object Drawing.Point(33, 412)
    $quotaStatus.ForeColor = [Drawing.Color]::DimGray
    $form.Controls.Add($quotaStatus)

    $privacy = New-Object Windows.Forms.Label
    $privacy.ForeColor = [Drawing.Color]::DimGray
    $privacy.AutoSize = $false
    $privacy.Size = New-Object Drawing.Size(610, 30)
    $privacy.Location = New-Object Drawing.Point(33, 462)
    $form.Controls.Add($privacy)

    $quotaState = @{
        Process = $null
        OutputTask = $null
        ErrorTask = $null
        StartedAt = $null
        TimedOut = $false
        LastRemaining = $null
        LastData = $null
        ErrorKey = $null
        IsChecking = $false
    }

    $getProviderDisplay = {
        param($State)
        switch ([string]$State.Provider) {
            'openai' { & $text 'OfficialButton' }
            'honknet' { & $text 'HonknetButton' }
            'deepseek' { & $text 'DeepSeekButton' }
            'custom' {
                if ([string]$State.Display -match '\(legacy\)') {
                    (& $text 'HonknetButton') + (& $text 'LegacySuffix')
                }
                else { [string]$State.Display }
            }
            default { [string]$State.Display }
        }
    }

    $refresh = {
        $state = Get-CurrentState
        $status.Text = ((& $text 'CurrentStatus') -f (& $getProviderDisplay $state), $state.Model)
        $honkReady = Get-KeyPresent ([string]$definitions.honknet.env_key)
        $dsReady = Get-KeyPresent ([string]$definitions.deepseek.env_key)
        $catalogReady = Test-Catalog $definitions.deepseek
        $health.Text = ((& $text 'Health') -f `
            $(if ($honkReady) { & $text 'Ready' } else { & $text 'Missing' }), `
            $(if ($dsReady) { & $text 'Ready' } else { & $text 'Missing' }), `
            $(if ($catalogReady) { & $text 'CatalogReady' } else { & $text 'CatalogMissing' }))
        $health.ForeColor = if ($honkReady -and $dsReady -and $catalogReady) { [Drawing.Color]::ForestGreen } else { [Drawing.Color]::Firebrick }
    }

    $renderQuota = {
        $refreshQuotaButton.Text = if ($quotaState.IsChecking) { & $text 'Checking' } else { & $text 'Refresh' }
        if ($null -ne $quotaState.LastData) {
            $data = $quotaState.LastData
            $remaining = [double]$data.Remaining
            $quotaPercent.Text = ((& $text 'QuotaRemaining') -f $remaining)
            $quotaFill.Width = [math]::Max(1, [int][math]::Round($quotaTrack.ClientSize.Width * $remaining / 100))
            $color = if ($remaining -gt 50) {
                [Drawing.Color]::FromArgb(22, 163, 74)
            }
            elseif ($remaining -gt 20) {
                [Drawing.Color]::FromArgb(217, 119, 6)
            }
            else {
                [Drawing.Color]::FromArgb(220, 38, 38)
            }
            $quotaPercent.ForeColor = $color
            $quotaFill.BackColor = $color
            $quotaReset.Text = if ($null -ne $data.Reset) {
                ((& $text 'ResetAt') -f $data.Reset.ToString('yyyy-MM-dd HH:mm'))
            }
            else { & $text 'ResetNotReported' }

            $current = Get-CurrentState
            if ($current.Provider -ne 'openai' -and $remaining -gt 0) {
                $quotaStatus.Text = ((& $text 'RelayAvailable') -f $data.Checked.ToString('HH:mm:ss'), $QuotaRefreshSeconds)
                $quotaStatus.ForeColor = [Drawing.Color]::ForestGreen
            }
            elseif ($remaining -le 0) {
                $quotaStatus.Text = ((& $text 'QuotaExhausted') -f $data.Checked.ToString('HH:mm:ss'), $QuotaRefreshSeconds)
                $quotaStatus.ForeColor = [Drawing.Color]::Firebrick
            }
            else {
                $quotaStatus.Text = ((& $text 'QuotaAvailable') -f $data.Checked.ToString('HH:mm:ss'), $QuotaRefreshSeconds)
                $quotaStatus.ForeColor = [Drawing.Color]::ForestGreen
            }
            return
        }

        if ($null -ne $quotaState.ErrorKey) {
            $quotaPercent.Text = & $text 'QuotaUnavailable'
            $quotaPercent.ForeColor = [Drawing.Color]::Firebrick
            $quotaFill.Width = 1
            $quotaFill.BackColor = [Drawing.Color]::Firebrick
            $quotaReset.Text = & $text 'ResetUnknown'
            $quotaStatus.Text = ((& $text 'ErrorStatus') -f (& $text $quotaState.ErrorKey))
            $quotaStatus.ForeColor = [Drawing.Color]::Firebrick
            return
        }

        $quotaPercent.Text = & $text 'QuotaChecking'
        $quotaPercent.ForeColor = [Drawing.Color]::DimGray
        $quotaFill.Width = 1
        $quotaFill.BackColor = [Drawing.Color]::FromArgb(156, 163, 175)
        $quotaReset.Text = & $text 'ResetWaiting'
        $quotaStatus.Text = ((& $text 'AutoRefresh') -f $QuotaRefreshSeconds)
        $quotaStatus.ForeColor = [Drawing.Color]::DimGray
    }

    $showQuotaError = {
        param([string]$ErrorKey)
        $quotaState.LastData = $null
        $quotaState.ErrorKey = $ErrorKey
        $quotaState.IsChecking = $false
        & $renderQuota
    }

    $applyQuotaJson = {
        param([string]$JsonText)
        try {
            $data = $JsonText | ConvertFrom-Json
            $remaining = [math]::Max(0, [math]::Min(100, [double]$data.codex_remaining_percent))
            $checked = [DateTimeOffset]::Parse([string]$data.checked_at).ToLocalTime()
            $reset = if (-not [string]::IsNullOrWhiteSpace([string]$data.codex_resets_at_local)) {
                [DateTimeOffset]::Parse([string]$data.codex_resets_at_local).ToLocalTime()
            }
            else { $null }

            if ($null -ne $quotaState.LastRemaining -and [double]$quotaState.LastRemaining -le 0 -and $remaining -gt 0) {
                [System.Media.SystemSounds]::Asterisk.Play()
            }
            $quotaState.LastRemaining = $remaining
            $quotaState.LastData = [pscustomobject]@{ Remaining = $remaining; Reset = $reset; Checked = $checked }
            $quotaState.ErrorKey = $null
            $quotaState.IsChecking = $false
            & $renderQuota
        }
        catch {
            & $showQuotaError 'ErrorParseFailed'
        }
    }

    $startQuotaRefresh = {
        if ($null -ne $quotaState.Process -and -not $quotaState.Process.HasExited) { return }
        if (-not (Test-Path -LiteralPath $RateLimitsPath)) {
            & $showQuotaError 'ErrorReaderMissing'
            return
        }

        $startInfo = New-Object Diagnostics.ProcessStartInfo
        $startInfo.FileName = (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
        $startInfo.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$RateLimitsPath`" -Json -TimeoutSeconds 8"
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true

        $process = New-Object Diagnostics.Process
        $process.StartInfo = $startInfo
        [void]$process.Start()
        $quotaState.Process = $process
        $quotaState.OutputTask = $process.StandardOutput.ReadLineAsync()
        $quotaState.ErrorTask = $process.StandardError.ReadLineAsync()
        $quotaState.StartedAt = [DateTimeOffset]::Now
        $quotaState.TimedOut = $false
        $quotaState.IsChecking = $true
        $refreshQuotaButton.Enabled = $false
        & $renderQuota
    }

    $quotaPollTimer = New-Object Windows.Forms.Timer
    $quotaPollTimer.Interval = 500
    $quotaPollTimer.Add_Tick({
        $process = $quotaState.Process
        if ($null -eq $process) { return }
        if ($quotaState.OutputTask.IsCompleted -and -not [string]::IsNullOrWhiteSpace($quotaState.OutputTask.Result)) {
            $stdout = $quotaState.OutputTask.Result
            if (-not $process.HasExited) {
                [void]$process.WaitForExit(1000)
                if (-not $process.HasExited) { try { $process.Kill() } catch { } }
            }
            $process.Dispose()
            $quotaState.Process = $null
            $refreshQuotaButton.Enabled = $true
            & $applyQuotaJson $stdout
            return
        }
        if (-not $process.HasExited) {
            if (([DateTimeOffset]::Now - $quotaState.StartedAt).TotalSeconds -gt 30) {
                $quotaState.TimedOut = $true
                try { $process.Kill() } catch { }
            }
            return
        }

        $stdout = if ($quotaState.OutputTask.IsCompleted) { $quotaState.OutputTask.Result } else { '' }
        $stderr = if ($quotaState.ErrorTask.IsCompleted) { $quotaState.ErrorTask.Result } else { '' }
        $exitCode = $process.ExitCode
        $process.Dispose()
        $quotaState.Process = $null
        $refreshQuotaButton.Enabled = $true
        $quotaState.IsChecking = $false

        if ($quotaState.TimedOut) {
            & $showQuotaError 'ErrorTimedOut'
        }
        elseif ($exitCode -ne 0 -or [string]::IsNullOrWhiteSpace($stdout)) {
            & $showQuotaError 'ErrorCheckFailed'
        }
        else {
            & $applyQuotaJson $stdout
        }
    })

    $quotaAutoTimer = New-Object Windows.Forms.Timer
    $quotaAutoTimer.Interval = $QuotaRefreshSeconds * 1000
    $quotaAutoTimer.Add_Tick({ & $startQuotaRefresh })
    $refreshQuotaButton.Add_Click({ & $startQuotaRefresh })

    foreach ($providerButton in $providerButtons.Values) {
        $providerButton.Add_Click({
            $provider = [string]$this.Tag
            $providerLabel = switch ($provider) {
                'official' { & $text 'OfficialButton' }
                'honknet' { & $text 'HonknetButton' }
                'deepseek' { & $text 'DeepSeekButton' }
            }
            $answer = [Windows.Forms.MessageBox]::Show(
                ((& $text 'ConfirmMessage') -f $providerLabel),
                (& $text 'ConfirmTitle'),
                [Windows.Forms.MessageBoxButtons]::OKCancel,
                [Windows.Forms.MessageBoxIcon]::Warning
            )
            if ($answer -ne [Windows.Forms.DialogResult]::OK) { return }
            try {
                if (Set-CodexProvider $provider $false) {
                    & $refresh
                    & $renderQuota
                    [Windows.Forms.MessageBox]::Show(
                        (& $text 'SwitchDone'),
                        (& $text 'SwitchDoneTitle'),
                        [Windows.Forms.MessageBoxButtons]::OK,
                        [Windows.Forms.MessageBoxIcon]::Information
                    ) | Out-Null
                }
            }
            catch {
                $message = if ($uiState.Language -eq 'zh-CN') {
                    switch -Regex ($_.Exception.Message) {
                        'Official OpenAI login' { & $text 'FriendlyLoginMissing'; break }
                        'environment variable' { & $text 'FriendlyKeyMissing'; break }
                        'model catalog' { & $text 'FriendlyCatalogMissing'; break }
                        'Config file not found' { & $text 'FriendlyConfigMissing'; break }
                        default { ((& $text 'FriendlyFailure') -f $_.Exception.Message) }
                    }
                }
                else { $_.Exception.Message }
                [Windows.Forms.MessageBox]::Show(
                    $message,
                    (& $text 'SwitchFailedTitle'),
                    [Windows.Forms.MessageBoxButtons]::OK,
                    [Windows.Forms.MessageBoxIcon]::Error
                ) | Out-Null
            }
        })
    }

    $updateLanguage = {
        $form.Text = & $text 'FormTitle'
        $title.Text = & $text 'Title'
        $languageButton.Text = & $text 'LanguageButton'
        $hint.Text = & $text 'Hint'
        $providerButtons['official'].Text = & $text 'OfficialButton'
        $providerButtons['honknet'].Text = & $text 'HonknetButton'
        $providerButtons['deepseek'].Text = & $text 'DeepSeekButton'
        $quotaTitle.Text = & $text 'QuotaTitle'
        $privacy.Text = & $text 'Privacy'
        & $refresh
        & $renderQuota
    }

    $languageButton.Add_Click({
        $uiState.Language = if ($uiState.Language -eq 'zh-CN') { 'en' } else { 'zh-CN' }
        & $updateLanguage
    })

    $form.Add_FormClosing({
        $quotaAutoTimer.Stop()
        $quotaPollTimer.Stop()
        if ($null -ne $quotaState.Process -and -not $quotaState.Process.HasExited) {
            try { $quotaState.Process.Kill() } catch { }
        }
    })

    & $updateLanguage
    $quotaPollTimer.Start()
    $quotaAutoTimer.Start()
    & $startQuotaRefresh
    [void]$form.ShowDialog()
}

$normalizedMode = switch ($Mode) {
    'gpt' { 'official' }
    'honkai' { 'honknet' }
    'ds' { 'deepseek' }
    default { $Mode }
}

if ($normalizedMode -eq 'gui') { Show-Switcher }
elseif ($normalizedMode -eq 'status') { Get-CurrentState | Format-List }
else { [void](Set-CodexProvider $normalizedMode $false) }
