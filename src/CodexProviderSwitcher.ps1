param(
    [ValidateSet('gui', 'official', 'gpt', 'honkai', 'honknet', 'deepseek', 'ds', 'status')]
    [string]$Mode = 'gui',
    [string]$ConfigPath = (Join-Path $env:USERPROFILE '.codex\config.toml'),
    [string]$ProvidersPath = (Join-Path $PSScriptRoot 'providers.json'),
    [string]$RateLimitsPath = (Join-Path $PSScriptRoot 'Get-CodexRateLimits.ps1'),
    [string]$DeepSeekBalancePath = (Join-Path $PSScriptRoot 'Get-DeepSeekBalance.ps1'),
    [string]$HonkaiUsagePath = (Join-Path $PSScriptRoot 'Get-HonkaiUsage.ps1'),
    [ValidateRange(15, 3600)]
    [int]$QuotaRefreshSeconds = 60,
    [ValidateSet('zh-CN', 'en')]
    [string]$Language = 'zh-CN',
    [switch]$NoRestart
)

$ErrorActionPreference = 'Stop'
$AppId = 'OpenAI.Codex_2p2nqsd0c76g0!App'
# Release format: V_<major>.<minor>_<YYMMDD>.<daily-sequence>
$AppVersion = 'V_1.3_260829.02'
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
            Subtitle = 'Token · Model 路由管理器'
            VersionLabel = '版本 {0}'
            LanguageButton = 'English'
            RouteOverview = '当前路由'
            ProviderRoutes = '可用线路'
            UsageOverview = '额度与用量'
            ActiveRoute = '当前线路'
            SwitchRoute = '切换到此线路'
            Healthy = '运行正常'
            Attention = '需要配置'
            ModelLabel = '模型  {0}'
            KeyReadyLabel = 'API 密钥已配置'
            KeyMissingLabel = 'API 密钥未配置'
            OfficialAuthReady = '官方登录可用'
            OfficialAuthMissing = '未检测到官方登录'
            LastSync = '每 {0} 秒自动刷新'
            CurrentStatus = '当前线路：{0}    模型：{1}'
            CurrentProvider = '当前线路：{0}'
            CurrentModel = '模型：{0}'
            Hint = "切换前请保存当前任务。`r`nCodex 重启后请新建任务。"
            OfficialButton = 'GPT 官方'
            HonknetButton = 'Honknet'
            DeepSeekButton = 'DeepSeek'
            LegacySuffix = '（旧配置）'
            Health = 'Honknet 密钥：{0}    DeepSeek 密钥：{1}    模型目录：{2}'
            HealthSummary = '密钥 {0}/2  ·  模型目录 {1}'
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
            DeepSeekQuotaTitle = 'DeepSeek 余额'
            DeepSeekBalance = 'DeepSeek 余额：{0:N2} {1}'
            DeepSeekChecking = 'DeepSeek 余额：检测中...'
            DeepSeekUnavailable = 'DeepSeek 余额：暂不可用'
            DeepSeekBreakdown = '充值：{0:N2} {1}    赠送：{2:N2} {3}'
            DeepSeekStatusAvailable = "DeepSeek 余额可用。`r`n更新时间 {0}；每 {1} 秒自动刷新。"
            DeepSeekStatusLow = "DeepSeek 余额不足，请及时充值。`r`n更新时间 {0}；每 {1} 秒自动刷新。"
            DeepSeekStatusBlocked = "DeepSeek 余额不可用于 API 调用。`r`n更新时间 {0}；每 {1} 秒自动刷新。"
            DeepSeekMissingKey = 'DeepSeek 密钥未配置，无法查询余额。'
            DeepSeekErrorReaderMissing = '未找到 DeepSeek 余额读取器，请重新安装本工具。'
            DeepSeekErrorParseFailed = '无法解析 DeepSeek 余额数据。'
            DeepSeekErrorTimedOut = 'DeepSeek 余额查询超时。'
            DeepSeekErrorCheckFailed = 'DeepSeek 余额查询失败，请检查 DeepSeek Key 和网络。'
            DeepSeekErrorStatus = "{0}`r`n线路切换功能仍可正常使用。"
            HonkaiQuotaTitle = 'Honknet 额度'
            HonkaiBalance = 'Honknet 剩余额度：{0:N2} {1}'
            HonkaiChecking = 'Honknet 额度：检测中...'
            HonkaiUnavailable = 'Honknet 额度：暂不可用'
            HonkaiBreakdown = '今日：{0:N0} 请求，{1:N0} tokens，{2:N2} {3}`r`n本月用量：{4:N2} {5}'
            HonkaiStatusAvailable = "Honknet 额度可用。`r`n更新时间 {0}；每 {1} 秒自动刷新。"
            HonkaiStatusLow = "Honknet 额度不足，请及时关注。`r`n更新时间 {0}；每 {1} 秒自动刷新。"
            HonkaiMissingKey = 'Honknet/HonkAI 密钥未配置，无法查询额度。'
            HonkaiErrorReaderMissing = '未找到 Honknet 额度读取器，请重新安装本工具。'
            HonkaiErrorParseFailed = '无法解析 Honknet 额度数据。'
            HonkaiErrorTimedOut = 'Honknet 额度查询超时。'
            HonkaiErrorCheckFailed = 'Honknet 额度查询失败，请检查密钥和网络。'
            HonkaiErrorStatus = "{0}`r`n线路切换功能仍可正常使用。"
            Privacy = '密钥仅从 Windows 环境变量读取；切换前会自动备份配置。'
        }
        'en' = @{
            FormTitle = 'Codex Three-Provider Switcher'
            Title = 'Codex Provider Switcher'
            Subtitle = 'Token · Model Routing Manager'
            VersionLabel = 'Version {0}'
            LanguageButton = '中文'
            RouteOverview = 'ACTIVE ROUTE'
            ProviderRoutes = 'AVAILABLE ROUTES'
            UsageOverview = 'QUOTA & USAGE'
            ActiveRoute = 'Active route'
            SwitchRoute = 'Use this route'
            Healthy = 'Healthy'
            Attention = 'Setup required'
            ModelLabel = 'Model  {0}'
            KeyReadyLabel = 'API key configured'
            KeyMissingLabel = 'API key missing'
            OfficialAuthReady = 'Official sign-in ready'
            OfficialAuthMissing = 'Official sign-in not found'
            LastSync = 'Auto refresh every {0}s'
            CurrentStatus = 'Current provider: {0}    Model: {1}'
            CurrentProvider = 'Provider: {0}'
            CurrentModel = 'Model: {0}'
            Hint = "Save the current task before switching.`r`nCreate a new task after Codex restarts."
            OfficialButton = 'GPT Official'
            HonknetButton = 'Honknet'
            DeepSeekButton = 'DeepSeek'
            LegacySuffix = ' (legacy)'
            Health = 'Honknet Key: {0}    DeepSeek Key: {1}    Catalog: {2}'
            HealthSummary = 'Keys {0}/2  ·  Catalog {1}'
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
            DeepSeekQuotaTitle = 'DeepSeek Balance'
            DeepSeekBalance = 'DeepSeek balance: {0:N2} {1}'
            DeepSeekChecking = 'DeepSeek balance: Checking...'
            DeepSeekUnavailable = 'DeepSeek balance: Unavailable'
            DeepSeekBreakdown = 'Topped up: {0:N2} {1}    Granted: {2:N2} {3}'
            DeepSeekStatusAvailable = "DeepSeek balance is available.`r`nUpdated {0}; auto refresh every {1} seconds."
            DeepSeekStatusLow = "DeepSeek balance is low. Add credits soon.`r`nUpdated {0}; auto refresh every {1} seconds."
            DeepSeekStatusBlocked = "DeepSeek balance cannot be used for API calls.`r`nUpdated {0}; auto refresh every {1} seconds."
            DeepSeekMissingKey = 'DeepSeek API key is not configured. Balance query is unavailable.'
            DeepSeekErrorReaderMissing = 'DeepSeek balance reader was not found. Reinstall this tool.'
            DeepSeekErrorParseFailed = 'The DeepSeek balance response could not be parsed.'
            DeepSeekErrorTimedOut = 'DeepSeek balance check timed out.'
            DeepSeekErrorCheckFailed = 'DeepSeek balance check failed. Check the key and network.'
            DeepSeekErrorStatus = "{0}`r`nThe provider switcher remains available."
            HonkaiQuotaTitle = 'Honknet Usage'
            HonkaiBalance = 'Honknet remaining: {0:N2} {1}'
            HonkaiChecking = 'Honknet usage: Checking...'
            HonkaiUnavailable = 'Honknet usage: Unavailable'
            HonkaiBreakdown = 'Today: {0:N0} requests, {1:N0} tokens, {2:N2} {3}`r`nMonthly used: {4:N2} {5}'
            HonkaiStatusAvailable = "Honknet usage is available.`r`nUpdated {0}; auto refresh every {1} seconds."
            HonkaiStatusLow = "Honknet usage is low. Top up soon.`r`nUpdated {0}; auto refresh every {1} seconds."
            HonkaiMissingKey = 'Honknet/HonkAI API key is not configured. Usage query is unavailable.'
            HonkaiErrorReaderMissing = 'Honknet usage reader was not found. Reinstall this tool.'
            HonkaiErrorParseFailed = 'The Honknet usage response could not be parsed.'
            HonkaiErrorTimedOut = 'Honknet usage check timed out.'
            HonkaiErrorCheckFailed = 'Honknet usage check failed. Check the key and network.'
            HonkaiErrorStatus = "{0}`r`nThe provider switcher remains available."
            Privacy = 'Keys come only from Windows environment variables. Config is backed up.'
        }
    }
    $text = { param([string]$Key) [string]$strings[$uiState.Language][$Key] }

    $theme = @{
        Canvas = [Drawing.Color]::FromArgb(246, 247, 249)
        Surface = [Drawing.Color]::White
        Border = [Drawing.Color]::FromArgb(226, 228, 232)
        Text = [Drawing.Color]::FromArgb(24, 24, 27)
        Muted = [Drawing.Color]::FromArgb(113, 113, 122)
        Primary = [Drawing.Color]::FromArgb(37, 99, 235)
        PrimarySoft = [Drawing.Color]::FromArgb(239, 246, 255)
        Success = [Drawing.Color]::FromArgb(22, 163, 74)
        Warning = [Drawing.Color]::FromArgb(217, 119, 6)
        Danger = [Drawing.Color]::FromArgb(220, 38, 38)
        Track = [Drawing.Color]::FromArgb(232, 234, 238)
    }

    $form = New-Object Windows.Forms.Form
    $form.ClientSize = New-Object Drawing.Size(960, 720)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.BackColor = $theme.Canvas
    $form.ForeColor = $theme.Text
    $form.Font = New-Object Drawing.Font('Microsoft YaHei UI', 9)

    $newCard = {
        param([Drawing.Point]$Location, [Drawing.Size]$Size)
        $outer = New-Object Windows.Forms.Panel
        $outer.Location = $Location
        $outer.Size = $Size
        $outer.BackColor = $theme.Border
        $inner = New-Object Windows.Forms.Panel
        $inner.Location = New-Object Drawing.Point(1, 1)
        $inner.Size = New-Object Drawing.Size(($Size.Width - 2), ($Size.Height - 2))
        $inner.BackColor = $theme.Surface
        $outer.Controls.Add($inner)
        $form.Controls.Add($outer)
        return @{ Outer = $outer; Inner = $inner }
    }

    $styleButton = {
        param([Windows.Forms.Button]$Button, [bool]$Primary)
        $Button.FlatStyle = 'Flat'
        $Button.FlatAppearance.BorderSize = if ($Primary) { 0 } else { 1 }
        $Button.FlatAppearance.BorderColor = $theme.Border
        $Button.BackColor = if ($Primary) { $theme.Primary } else { $theme.Surface }
        $Button.ForeColor = if ($Primary) { [Drawing.Color]::White } else { $theme.Text }
        $Button.Cursor = [Windows.Forms.Cursors]::Hand
    }

    $title = New-Object Windows.Forms.Label
    $title.Font = New-Object Drawing.Font('Microsoft YaHei UI', 18, [Drawing.FontStyle]::Bold)
    $title.AutoSize = $true
    $title.Location = New-Object Drawing.Point(32, 20)
    $form.Controls.Add($title)

    $subtitle = New-Object Windows.Forms.Label
    $subtitle.AutoSize = $true
    $subtitle.ForeColor = $theme.Muted
    $subtitle.Location = New-Object Drawing.Point(34, 55)
    $form.Controls.Add($subtitle)

    $versionLabel = New-Object Windows.Forms.Label
    $versionLabel.AutoSize = $true
    $versionLabel.ForeColor = $theme.Muted
    $versionLabel.Location = New-Object Drawing.Point(310, 55)
    $form.Controls.Add($versionLabel)

    $languageButton = New-Object Windows.Forms.Button
    $languageButton.Size = New-Object Drawing.Size(82, 34)
    $languageButton.Location = New-Object Drawing.Point(846, 22)
    & $styleButton $languageButton $false
    $form.Controls.Add($languageButton)

    $refreshQuotaButton = New-Object Windows.Forms.Button
    $refreshQuotaButton.Size = New-Object Drawing.Size(92, 34)
    $refreshQuotaButton.Location = New-Object Drawing.Point(742, 22)
    & $styleButton $refreshQuotaButton $false
    $form.Controls.Add($refreshQuotaButton)

    $syncStatus = New-Object Windows.Forms.Label
    $syncStatus.Size = New-Object Drawing.Size(300, 20)
    $syncStatus.Location = New-Object Drawing.Point(530, 61)
    $syncStatus.TextAlign = [Drawing.ContentAlignment]::MiddleRight
    $syncStatus.ForeColor = $theme.Muted
    $form.Controls.Add($syncStatus)

    $routeSection = New-Object Windows.Forms.Label
    $routeSection.Font = New-Object Drawing.Font('Microsoft YaHei UI', 9, [Drawing.FontStyle]::Bold)
    $routeSection.ForeColor = $theme.Muted
    $routeSection.AutoSize = $true
    $routeSection.Location = New-Object Drawing.Point(32, 92)
    $form.Controls.Add($routeSection)

    $currentCard = & $newCard (New-Object Drawing.Point(32, 116)) (New-Object Drawing.Size(896, 88))
    $currentStripe = New-Object Windows.Forms.Panel
    $currentStripe.Location = New-Object Drawing.Point(0, 0)
    $currentStripe.Size = New-Object Drawing.Size(4, 86)
    $currentStripe.BackColor = $theme.Primary
    $currentCard.Inner.Controls.Add($currentStripe)

    $statusDot = New-Object Windows.Forms.Label
    $statusDot.Text = '●'
    $statusDot.ForeColor = $theme.Success
    $statusDot.Font = New-Object Drawing.Font('Segoe UI', 11)
    $statusDot.AutoSize = $true
    $statusDot.Location = New-Object Drawing.Point(22, 18)
    $currentCard.Inner.Controls.Add($statusDot)

    $status = New-Object Windows.Forms.Label
    $status.Font = New-Object Drawing.Font('Microsoft YaHei UI', 12, [Drawing.FontStyle]::Bold)
    $status.Size = New-Object Drawing.Size(270, 26)
    $status.Location = New-Object Drawing.Point(46, 16)
    $currentCard.Inner.Controls.Add($status)

    $currentModel = New-Object Windows.Forms.Label
    $currentModel.Font = New-Object Drawing.Font('Microsoft YaHei UI', 12, [Drawing.FontStyle]::Bold)
    $currentModel.Size = New-Object Drawing.Size(300, 26)
    $currentModel.Location = New-Object Drawing.Point(330, 16)
    $currentModel.ForeColor = $theme.Success
    $currentCard.Inner.Controls.Add($currentModel)

    $hint = New-Object Windows.Forms.Label
    $hint.Size = New-Object Drawing.Size(540, 34)
    $hint.Location = New-Object Drawing.Point(48, 47)
    $hint.ForeColor = $theme.Muted
    $currentCard.Inner.Controls.Add($hint)

    $health = New-Object Windows.Forms.Label
    $health.Size = New-Object Drawing.Size(278, 50)
    $health.Location = New-Object Drawing.Point(590, 20)
    $health.TextAlign = [Drawing.ContentAlignment]::MiddleRight
    $health.ForeColor = $theme.Muted
    $currentCard.Inner.Controls.Add($health)

    $providerSection = New-Object Windows.Forms.Label
    $providerSection.Font = New-Object Drawing.Font('Microsoft YaHei UI', 9, [Drawing.FontStyle]::Bold)
    $providerSection.ForeColor = $theme.Muted
    $providerSection.AutoSize = $true
    $providerSection.Location = New-Object Drawing.Point(32, 222)
    $form.Controls.Add($providerSection)

    $buttonSpecs = @(
        @{ TextKey = 'OfficialButton'; Provider = 'official'; X = 32; Color = [Drawing.Color]::FromArgb(16, 163, 127) },
        @{ TextKey = 'HonknetButton'; Provider = 'honknet'; X = 336; Color = [Drawing.Color]::FromArgb(37, 99, 235) },
        @{ TextKey = 'DeepSeekButton'; Provider = 'deepseek'; X = 640; Color = [Drawing.Color]::FromArgb(109, 40, 217) }
    )

    $providerButtons = @{}
    $providerCards = @{}
    $providerNameLabels = @{}
    $providerStatusLabels = @{}
    $providerModelLabels = @{}
    $providerKeyLabels = @{}
    $providerSoft = @{
        official = [Drawing.Color]::FromArgb(240, 253, 250)
        honknet = [Drawing.Color]::FromArgb(239, 246, 255)
        deepseek = [Drawing.Color]::FromArgb(250, 245, 255)
    }

    foreach ($spec in $buttonSpecs) {
        $card = & $newCard (New-Object Drawing.Point($spec.X, 246)) (New-Object Drawing.Size(288, 148))
        $card.Inner.BackColor = $providerSoft[$spec.Provider]
        $stripe = New-Object Windows.Forms.Panel
        $stripe.Location = New-Object Drawing.Point(0, 0)
        $stripe.Size = New-Object Drawing.Size(286, 3)
        $stripe.BackColor = $spec.Color
        $card.Inner.Controls.Add($stripe)

        $name = New-Object Windows.Forms.Label
        $name.Font = New-Object Drawing.Font('Microsoft YaHei UI', 11, [Drawing.FontStyle]::Bold)
        $name.AutoSize = $true
        $name.Location = New-Object Drawing.Point(16, 14)
        $card.Inner.Controls.Add($name)

        $providerStatus = New-Object Windows.Forms.Label
        $providerStatus.Size = New-Object Drawing.Size(120, 22)
        $providerStatus.Location = New-Object Drawing.Point(150, 15)
        $providerStatus.TextAlign = [Drawing.ContentAlignment]::MiddleRight
        $card.Inner.Controls.Add($providerStatus)

        $model = New-Object Windows.Forms.Label
        $model.Size = New-Object Drawing.Size(254, 20)
        $model.Location = New-Object Drawing.Point(16, 47)
        $model.ForeColor = $theme.Muted
        $model.AutoEllipsis = $true
        $card.Inner.Controls.Add($model)

        $key = New-Object Windows.Forms.Label
        $key.Size = New-Object Drawing.Size(254, 20)
        $key.Location = New-Object Drawing.Point(16, 70)
        $key.ForeColor = $theme.Muted
        $card.Inner.Controls.Add($key)

        $button = New-Object Windows.Forms.Button
        $button.Tag = $spec.Provider
        $button.Size = New-Object Drawing.Size(254, 32)
        $button.Location = New-Object Drawing.Point(16, 102)
        & $styleButton $button $false
        $button.FlatAppearance.BorderColor = $spec.Color
        $card.Inner.Controls.Add($button)

        $providerButtons[$spec.Provider] = $button
        $providerCards[$spec.Provider] = $card
        $providerNameLabels[$spec.Provider] = $name
        $providerStatusLabels[$spec.Provider] = $providerStatus
        $providerModelLabels[$spec.Provider] = $model
        $providerKeyLabels[$spec.Provider] = $key
    }

    $usageSection = New-Object Windows.Forms.Label
    $usageSection.Font = New-Object Drawing.Font('Microsoft YaHei UI', 9, [Drawing.FontStyle]::Bold)
    $usageSection.ForeColor = $theme.Muted
    $usageSection.AutoSize = $true
    $usageSection.Location = New-Object Drawing.Point(32, 414)
    $form.Controls.Add($usageSection)

    $officialUsageCard = & $newCard (New-Object Drawing.Point(32, 438)) (New-Object Drawing.Size(288, 224))
    $honkaiUsageCard = & $newCard (New-Object Drawing.Point(336, 438)) (New-Object Drawing.Size(288, 224))
    $deepseekUsageCard = & $newCard (New-Object Drawing.Point(640, 438)) (New-Object Drawing.Size(288, 224))

    $quotaTitle = New-Object Windows.Forms.Label
    $quotaTitle.Font = New-Object Drawing.Font('Microsoft YaHei UI', 11, [Drawing.FontStyle]::Bold)
    $quotaTitle.AutoSize = $true
    $quotaTitle.Location = New-Object Drawing.Point(16, 16)
    $officialUsageCard.Inner.Controls.Add($quotaTitle)

    $quotaPercent = New-Object Windows.Forms.Label
    $quotaPercent.Size = New-Object Drawing.Size(254, 28)
    $quotaPercent.Font = New-Object Drawing.Font('Microsoft YaHei UI', 12, [Drawing.FontStyle]::Bold)
    $quotaPercent.Location = New-Object Drawing.Point(16, 50)
    $officialUsageCard.Inner.Controls.Add($quotaPercent)

    $quotaTrack = New-Object Windows.Forms.Panel
    $quotaTrack.Size = New-Object Drawing.Size(254, 8)
    $quotaTrack.Location = New-Object Drawing.Point(16, 84)
    $quotaTrack.BackColor = $theme.Track
    $officialUsageCard.Inner.Controls.Add($quotaTrack)

    $quotaFill = New-Object Windows.Forms.Panel
    $quotaFill.Size = New-Object Drawing.Size(1, 8)
    $quotaFill.Location = New-Object Drawing.Point(0, 0)
    $quotaFill.BackColor = [Drawing.Color]::FromArgb(156, 163, 175)
    $quotaTrack.Controls.Add($quotaFill)

    $quotaReset = New-Object Windows.Forms.Label
    $quotaReset.Size = New-Object Drawing.Size(254, 22)
    $quotaReset.Location = New-Object Drawing.Point(16, 106)
    $quotaReset.ForeColor = $theme.Muted
    $officialUsageCard.Inner.Controls.Add($quotaReset)

    $quotaStatus = New-Object Windows.Forms.Label
    $quotaStatus.Size = New-Object Drawing.Size(254, 62)
    $quotaStatus.Location = New-Object Drawing.Point(16, 142)
    $quotaStatus.ForeColor = $theme.Muted
    $officialUsageCard.Inner.Controls.Add($quotaStatus)

    $honkaiQuotaTitle = New-Object Windows.Forms.Label
    $honkaiQuotaTitle.Font = New-Object Drawing.Font('Microsoft YaHei UI', 11, [Drawing.FontStyle]::Bold)
    $honkaiQuotaTitle.AutoSize = $true
    $honkaiQuotaTitle.Location = New-Object Drawing.Point(16, 16)
    $honkaiUsageCard.Inner.Controls.Add($honkaiQuotaTitle)

    $honkaiBalance = New-Object Windows.Forms.Label
    $honkaiBalance.Size = New-Object Drawing.Size(254, 28)
    $honkaiBalance.Font = New-Object Drawing.Font('Microsoft YaHei UI', 12, [Drawing.FontStyle]::Bold)
    $honkaiBalance.Location = New-Object Drawing.Point(16, 50)
    $honkaiUsageCard.Inner.Controls.Add($honkaiBalance)

    $honkaiBreakdown = New-Object Windows.Forms.Label
    $honkaiBreakdown.Size = New-Object Drawing.Size(254, 54)
    $honkaiBreakdown.Location = New-Object Drawing.Point(16, 88)
    $honkaiBreakdown.ForeColor = $theme.Muted
    $honkaiUsageCard.Inner.Controls.Add($honkaiBreakdown)

    $honkaiStatus = New-Object Windows.Forms.Label
    $honkaiStatus.Size = New-Object Drawing.Size(254, 58)
    $honkaiStatus.Location = New-Object Drawing.Point(16, 146)
    $honkaiStatus.ForeColor = $theme.Muted
    $honkaiUsageCard.Inner.Controls.Add($honkaiStatus)

    $deepseekQuotaTitle = New-Object Windows.Forms.Label
    $deepseekQuotaTitle.Font = New-Object Drawing.Font('Microsoft YaHei UI', 11, [Drawing.FontStyle]::Bold)
    $deepseekQuotaTitle.AutoSize = $true
    $deepseekQuotaTitle.Location = New-Object Drawing.Point(16, 16)
    $deepseekUsageCard.Inner.Controls.Add($deepseekQuotaTitle)

    $deepseekBalance = New-Object Windows.Forms.Label
    $deepseekBalance.Size = New-Object Drawing.Size(254, 28)
    $deepseekBalance.Font = New-Object Drawing.Font('Microsoft YaHei UI', 12, [Drawing.FontStyle]::Bold)
    $deepseekBalance.Location = New-Object Drawing.Point(16, 50)
    $deepseekUsageCard.Inner.Controls.Add($deepseekBalance)

    $deepseekBreakdown = New-Object Windows.Forms.Label
    $deepseekBreakdown.Size = New-Object Drawing.Size(254, 38)
    $deepseekBreakdown.Location = New-Object Drawing.Point(16, 88)
    $deepseekBreakdown.ForeColor = $theme.Muted
    $deepseekUsageCard.Inner.Controls.Add($deepseekBreakdown)

    $deepseekStatus = New-Object Windows.Forms.Label
    $deepseekStatus.Size = New-Object Drawing.Size(254, 70)
    $deepseekStatus.Location = New-Object Drawing.Point(16, 134)
    $deepseekStatus.ForeColor = $theme.Muted
    $deepseekUsageCard.Inner.Controls.Add($deepseekStatus)

    $privacy = New-Object Windows.Forms.Label
    $privacy.ForeColor = $theme.Muted
    $privacy.Size = New-Object Drawing.Size(896, 28)
    $privacy.Location = New-Object Drawing.Point(32, 682)
    $privacy.TextAlign = [Drawing.ContentAlignment]::MiddleLeft
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

    $deepseekState = @{
        Process = $null
        OutputTask = $null
        ErrorTask = $null
        StartedAt = $null
        TimedOut = $false
        LastData = $null
        ErrorKey = $null
        IsChecking = $false
    }

    $honkaiState = @{
        Process = $null
        OutputTask = $null
        ErrorTask = $null
        StartedAt = $null
        TimedOut = $false
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
        $status.Text = ((& $text 'CurrentProvider') -f (& $getProviderDisplay $state))
        $currentModel.Text = ((& $text 'CurrentModel') -f $state.Model)
        $currentModel.ForeColor = $theme.Success
        $authPath = Join-Path (Split-Path -Parent $ConfigPath) 'auth.json'
        $officialReady = Test-Path -LiteralPath $authPath
        $honkReady = (Get-KeyPresent 'HONKNET_API_KEY') -or (Get-KeyPresent 'HONKAI_API_KEY')
        $dsReady = Get-KeyPresent ([string]$definitions.deepseek.env_key)
        $catalogReady = Test-Catalog $definitions.deepseek
        $providerReady = @{
            official = $officialReady
            honknet = $honkReady
            deepseek = ($dsReady -and $catalogReady)
        }
        $activeProvider = switch ([string]$state.Provider) {
            'openai' { 'official' }
            'honknet' { 'honknet' }
            'deepseek' { 'deepseek' }
            'custom' { if ([string]$state.Display -match 'legacy') { 'honknet' } else { 'unknown' } }
            default { 'unknown' }
        }

        foreach ($provider in @('official', 'honknet', 'deepseek')) {
            $isActive = $provider -eq $activeProvider
            $isReady = [bool]$providerReady[$provider]
            $providerCards[$provider].Outer.BackColor = if ($isActive) { $theme.Primary } else { $theme.Border }
            $providerStatusLabels[$provider].Text = if ($isActive) {
                '● ' + (& $text 'ActiveRoute')
            }
            elseif ($isReady) {
                '● ' + (& $text 'Healthy')
            }
            else {
                '● ' + (& $text 'Attention')
            }
            $providerStatusLabels[$provider].ForeColor = if ($isActive) {
                $theme.Primary
            }
            elseif ($isReady) {
                $theme.Success
            }
            else {
                $theme.Warning
            }
            $providerModelLabels[$provider].Text = ((& $text 'ModelLabel') -f [string]$definitions.$provider.model)
            $providerKeyLabels[$provider].Text = if ($provider -eq 'official') {
                if ($officialReady) { & $text 'OfficialAuthReady' } else { & $text 'OfficialAuthMissing' }
            }
            elseif ($isReady) {
                & $text 'KeyReadyLabel'
            }
            else {
                & $text 'KeyMissingLabel'
            }
            $providerKeyLabels[$provider].ForeColor = if ($isReady) { $theme.Muted } else { $theme.Warning }
            $providerButtons[$provider].Enabled = -not $isActive
            $providerButtons[$provider].Text = if ($isActive) { & $text 'ActiveRoute' } else { & $text 'SwitchRoute' }
            $providerButtons[$provider].BackColor = if ($isActive) { $theme.PrimarySoft } else { $theme.Surface }
            $providerButtons[$provider].ForeColor = if ($isActive) { $theme.Primary } else { $theme.Text }
        }

        $activeReady = if ($providerReady.ContainsKey($activeProvider)) { [bool]$providerReady[$activeProvider] } else { $false }
        $statusDot.ForeColor = if ($activeReady) { $theme.Success } else { $theme.Warning }
        $configuredKeyCount = [int][bool]$honkReady + [int][bool]$dsReady
        $health.Text = ((& $text 'HealthSummary') -f `
            $configuredKeyCount, `
            $(if ($catalogReady) { & $text 'CatalogReady' } else { & $text 'CatalogMissing' }))
        $health.ForeColor = if ($honkReady -and $dsReady -and $catalogReady) { $theme.Success } else { $theme.Muted }
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

    $renderDeepSeek = {
        if ($null -ne $deepseekState.LastData) {
            $data = $deepseekState.LastData
            $currency = [string]$data.Currency
            $deepseekBalance.Text = ((& $text 'DeepSeekBalance') -f $data.TotalBalance, $currency)
            $deepseekBreakdown.Text = ((& $text 'DeepSeekBreakdown') -f `
                $data.ToppedUpBalance, $currency, $data.GrantedBalance, $currency)

            $lowThreshold = if ($currency -eq 'CNY') { 10d }
            elseif ($currency -eq 'USD') { 1d }
            else { 0d }
            if (-not $data.IsAvailable) {
                $deepseekBalance.ForeColor = [Drawing.Color]::Firebrick
                $deepseekStatus.Text = ((& $text 'DeepSeekStatusBlocked') -f `
                    $data.Checked.ToString('HH:mm:ss'), $QuotaRefreshSeconds)
                $deepseekStatus.ForeColor = [Drawing.Color]::Firebrick
            }
            elseif ($data.TotalBalance -le 0 -or $data.TotalBalance -le $lowThreshold) {
                $deepseekBalance.ForeColor = [Drawing.Color]::FromArgb(217, 119, 6)
                $deepseekStatus.Text = ((& $text 'DeepSeekStatusLow') -f `
                    $data.Checked.ToString('HH:mm:ss'), $QuotaRefreshSeconds)
                $deepseekStatus.ForeColor = [Drawing.Color]::FromArgb(217, 119, 6)
            }
            else {
                $deepseekBalance.ForeColor = [Drawing.Color]::FromArgb(22, 163, 74)
                $deepseekStatus.Text = ((& $text 'DeepSeekStatusAvailable') -f `
                    $data.Checked.ToString('HH:mm:ss'), $QuotaRefreshSeconds)
                $deepseekStatus.ForeColor = [Drawing.Color]::FromArgb(22, 163, 74)
            }
            return
        }

        if ($null -ne $deepseekState.ErrorKey) {
            $deepseekBalance.Text = & $text 'DeepSeekUnavailable'
            $deepseekBalance.ForeColor = [Drawing.Color]::Firebrick
            $deepseekBreakdown.Text = ''
            $deepseekStatus.Text = ((& $text 'DeepSeekErrorStatus') -f (& $text $deepseekState.ErrorKey))
            $deepseekStatus.ForeColor = [Drawing.Color]::Firebrick
            return
        }

        $deepseekBalance.Text = & $text 'DeepSeekChecking'
        $deepseekBalance.ForeColor = [Drawing.Color]::DimGray
        $deepseekBreakdown.Text = ''
        $deepseekStatus.Text = ((& $text 'AutoRefresh') -f $QuotaRefreshSeconds)
        $deepseekStatus.ForeColor = [Drawing.Color]::DimGray
    }

    $showDeepSeekError = {
        param([string]$ErrorKey)
        $deepseekState.LastData = $null
        $deepseekState.ErrorKey = $ErrorKey
        $deepseekState.IsChecking = $false
        & $renderDeepSeek
    }

    $applyDeepSeekJson = {
        param([string]$JsonText)
        try {
            $data = $JsonText | ConvertFrom-Json
            $total = [decimal]$data.total_balance
            $granted = [decimal]$data.granted_balance
            $toppedUp = [decimal]$data.topped_up_balance
            if ($total -lt 0) { $total = 0d }
            if ($granted -lt 0) { $granted = 0d }
            if ($toppedUp -lt 0) { $toppedUp = 0d }
            $checked = [DateTimeOffset]::Parse([string]$data.checked_at).ToLocalTime()
            $deepseekState.LastData = [pscustomobject]@{
                TotalBalance = $total
                GrantedBalance = $granted
                ToppedUpBalance = $toppedUp
                Currency = [string]$data.currency
                IsAvailable = [bool]$data.is_available
                Checked = $checked
            }
            $deepseekState.ErrorKey = $null
            $deepseekState.IsChecking = $false
            & $renderDeepSeek
        }
        catch {
            & $showDeepSeekError 'DeepSeekErrorParseFailed'
        }
    }

    $startDeepSeekRefresh = {
        if ($null -ne $deepseekState.Process -and -not $deepseekState.Process.HasExited) { return }
        if (-not (Test-Path -LiteralPath $DeepSeekBalancePath)) {
            & $showDeepSeekError 'DeepSeekErrorReaderMissing'
            return
        }
        if (-not (Get-KeyPresent ([string]$definitions.deepseek.env_key))) {
            & $showDeepSeekError 'DeepSeekMissingKey'
            return
        }

        $startInfo = New-Object Diagnostics.ProcessStartInfo
        $startInfo.FileName = (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
        $startInfo.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$DeepSeekBalancePath`" -Json -TimeoutSeconds 8"
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true

        $process = New-Object Diagnostics.Process
        $process.StartInfo = $startInfo
        [void]$process.Start()
        $deepseekState.Process = $process
        $deepseekState.OutputTask = $process.StandardOutput.ReadLineAsync()
        $deepseekState.ErrorTask = $process.StandardError.ReadLineAsync()
        $deepseekState.StartedAt = [DateTimeOffset]::Now
        $deepseekState.TimedOut = $false
        $deepseekState.IsChecking = $true
        $refreshQuotaButton.Enabled = $false
        & $renderDeepSeek
    }

    $deepseekPollTimer = New-Object Windows.Forms.Timer
    $deepseekPollTimer.Interval = 500
    $deepseekPollTimer.Add_Tick({
        $process = $deepseekState.Process
        if ($null -eq $process) { return }
        if ($deepseekState.OutputTask.IsCompleted -and -not [string]::IsNullOrWhiteSpace($deepseekState.OutputTask.Result)) {
            $stdout = $deepseekState.OutputTask.Result
            if (-not $process.HasExited) {
                [void]$process.WaitForExit(1000)
                if (-not $process.HasExited) { try { $process.Kill() } catch { } }
            }
            $process.Dispose()
            $deepseekState.Process = $null
            $refreshQuotaButton.Enabled = $true
            & $applyDeepSeekJson $stdout
            return
        }
        if (-not $process.HasExited) {
            if (([DateTimeOffset]::Now - $deepseekState.StartedAt).TotalSeconds -gt 30) {
                $deepseekState.TimedOut = $true
                try { $process.Kill() } catch { }
            }
            return
        }

        $stdout = if ($deepseekState.OutputTask.IsCompleted) { $deepseekState.OutputTask.Result } else { '' }
        $exitCode = $process.ExitCode
        $process.Dispose()
        $deepseekState.Process = $null
        $refreshQuotaButton.Enabled = $true
        $deepseekState.IsChecking = $false

        if ($deepseekState.TimedOut) {
            & $showDeepSeekError 'DeepSeekErrorTimedOut'
        }
        elseif ($exitCode -ne 0 -or [string]::IsNullOrWhiteSpace($stdout)) {
            & $showDeepSeekError 'DeepSeekErrorCheckFailed'
        }
        else {
            & $applyDeepSeekJson $stdout
        }
    })

    $renderHonkai = {
        $refreshQuotaButton.Text = if ($quotaState.IsChecking -or $deepseekState.IsChecking -or $honkaiState.IsChecking) {
            & $text 'Checking'
        }
        else {
            & $text 'Refresh'
        }
        if ($null -ne $honkaiState.LastData) {
            $data = $honkaiState.LastData
            $currency = [string]$data.Currency
            $honkaiBalance.Text = ((& $text 'HonkaiBalance') -f $data.Remaining, $currency)
            $honkaiBreakdown.Text = ((& $text 'HonkaiBreakdown') -f `
                $data.TodayRequests, $data.TodayTotalTokens, $data.TodayCost, $currency, `
                $data.MonthlyUsed, $currency)

            $lowThreshold = if ($currency -eq 'USD') { 1d } else { 0d }
            if ($data.Remaining -le 0 -or $data.Remaining -le $lowThreshold) {
                $honkaiBalance.ForeColor = [Drawing.Color]::FromArgb(217, 119, 6)
                $honkaiStatus.Text = ((& $text 'HonkaiStatusLow') -f `
                    $data.Checked.ToString('HH:mm:ss'), $QuotaRefreshSeconds)
                $honkaiStatus.ForeColor = [Drawing.Color]::FromArgb(217, 119, 6)
            }
            else {
                $honkaiBalance.ForeColor = [Drawing.Color]::FromArgb(22, 163, 74)
                $honkaiStatus.Text = ((& $text 'HonkaiStatusAvailable') -f `
                    $data.Checked.ToString('HH:mm:ss'), $QuotaRefreshSeconds)
                $honkaiStatus.ForeColor = [Drawing.Color]::FromArgb(22, 163, 74)
            }
            return
        }

        if ($null -ne $honkaiState.ErrorKey) {
            $honkaiBalance.Text = & $text 'HonkaiUnavailable'
            $honkaiBalance.ForeColor = [Drawing.Color]::Firebrick
            $honkaiBreakdown.Text = ''
            $honkaiStatus.Text = ((& $text 'HonkaiErrorStatus') -f (& $text $honkaiState.ErrorKey))
            $honkaiStatus.ForeColor = [Drawing.Color]::Firebrick
            return
        }

        $honkaiBalance.Text = & $text 'HonkaiChecking'
        $honkaiBalance.ForeColor = [Drawing.Color]::DimGray
        $honkaiBreakdown.Text = ''
        $honkaiStatus.Text = ((& $text 'AutoRefresh') -f $QuotaRefreshSeconds)
        $honkaiStatus.ForeColor = [Drawing.Color]::DimGray
    }

    $showHonkaiError = {
        param([string]$ErrorKey)
        $honkaiState.LastData = $null
        $honkaiState.ErrorKey = $ErrorKey
        $honkaiState.IsChecking = $false
        & $renderHonkai
    }

    $applyHonkaiJson = {
        param([string]$JsonText)
        try {
            $data = $JsonText | ConvertFrom-Json
            $remaining = [decimal]$data.remaining
            $monthlyUsed = [decimal]$data.monthly_used
            $todayRequests = [long]$data.today_requests
            $todayTotalTokens = [long]$data.today_total_tokens
            $todayCost = [decimal]$data.today_cost_usd
            if ($remaining -lt 0) { $remaining = 0d }
            if ($monthlyUsed -lt 0) { $monthlyUsed = 0d }
            $checked = [DateTimeOffset]::Parse([string]$data.checked_at).ToLocalTime()
            $honkaiState.LastData = [pscustomobject]@{
                Remaining = $remaining
                MonthlyUsed = $monthlyUsed
                TodayRequests = $todayRequests
                TodayTotalTokens = $todayTotalTokens
                TodayCost = $todayCost
                Currency = if ([string]::IsNullOrWhiteSpace([string]$data.currency)) { 'USD' } else { [string]$data.currency }
                Checked = $checked
            }
            $honkaiState.ErrorKey = $null
            $honkaiState.IsChecking = $false
            & $renderHonkai
        }
        catch {
            & $showHonkaiError 'HonkaiErrorParseFailed'
        }
    }

    $startHonkaiRefresh = {
        if ($null -ne $honkaiState.Process -and -not $honkaiState.Process.HasExited) { return }
        if (-not (Test-Path -LiteralPath $HonkaiUsagePath)) {
            & $showHonkaiError 'HonkaiErrorReaderMissing'
            return
        }
        if (-not ((Get-KeyPresent 'HONKNET_API_KEY') -or (Get-KeyPresent 'HONKAI_API_KEY'))) {
            & $showHonkaiError 'HonkaiMissingKey'
            return
        }

        $startInfo = New-Object Diagnostics.ProcessStartInfo
        $startInfo.FileName = (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
        $startInfo.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$HonkaiUsagePath`" -Json -TimeoutSeconds 8"
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true

        $process = New-Object Diagnostics.Process
        $process.StartInfo = $startInfo
        [void]$process.Start()
        $honkaiState.Process = $process
        $honkaiState.OutputTask = $process.StandardOutput.ReadLineAsync()
        $honkaiState.ErrorTask = $process.StandardError.ReadLineAsync()
        $honkaiState.StartedAt = [DateTimeOffset]::Now
        $honkaiState.TimedOut = $false
        $honkaiState.IsChecking = $true
        $refreshQuotaButton.Enabled = $false
        & $renderHonkai
    }

    $honkaiPollTimer = New-Object Windows.Forms.Timer
    $honkaiPollTimer.Interval = 500
    $honkaiPollTimer.Add_Tick({
        $process = $honkaiState.Process
        if ($null -eq $process) { return }
        if ($honkaiState.OutputTask.IsCompleted -and -not [string]::IsNullOrWhiteSpace($honkaiState.OutputTask.Result)) {
            $stdout = $honkaiState.OutputTask.Result
            if (-not $process.HasExited) {
                [void]$process.WaitForExit(1000)
                if (-not $process.HasExited) { try { $process.Kill() } catch { } }
            }
            $process.Dispose()
            $honkaiState.Process = $null
            $refreshQuotaButton.Enabled = $true
            & $applyHonkaiJson $stdout
            return
        }
        if (-not $process.HasExited) {
            if (([DateTimeOffset]::Now - $honkaiState.StartedAt).TotalSeconds -gt 30) {
                $honkaiState.TimedOut = $true
                try { $process.Kill() } catch { }
            }
            return
        }

        $stdout = if ($honkaiState.OutputTask.IsCompleted) { $honkaiState.OutputTask.Result } else { '' }
        $exitCode = $process.ExitCode
        $process.Dispose()
        $honkaiState.Process = $null
        $refreshQuotaButton.Enabled = $true
        $honkaiState.IsChecking = $false

        if ($honkaiState.TimedOut) {
            & $showHonkaiError 'HonkaiErrorTimedOut'
        }
        elseif ($exitCode -ne 0 -or [string]::IsNullOrWhiteSpace($stdout)) {
            & $showHonkaiError 'HonkaiErrorCheckFailed'
        }
        else {
            & $applyHonkaiJson $stdout
        }
    })

    $quotaAutoTimer = New-Object Windows.Forms.Timer
    $quotaAutoTimer.Interval = $QuotaRefreshSeconds * 1000
    $quotaAutoTimer.Add_Tick({ & $startQuotaRefresh })
    $deepseekAutoTimer = New-Object Windows.Forms.Timer
    $deepseekAutoTimer.Interval = $QuotaRefreshSeconds * 1000
    $deepseekAutoTimer.Add_Tick({ & $startDeepSeekRefresh })
    $honkaiAutoTimer = New-Object Windows.Forms.Timer
    $honkaiAutoTimer.Interval = $QuotaRefreshSeconds * 1000
    $honkaiAutoTimer.Add_Tick({ & $startHonkaiRefresh })
    $refreshQuotaButton.Add_Click({ & $startQuotaRefresh; & $startHonkaiRefresh; & $startDeepSeekRefresh })

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
                    & $renderDeepSeek
                    & $renderHonkai
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
        $subtitle.Text = & $text 'Subtitle'
        $versionLabel.Text = ((& $text 'VersionLabel') -f $AppVersion)
        $languageButton.Text = & $text 'LanguageButton'
        $routeSection.Text = & $text 'RouteOverview'
        $providerSection.Text = & $text 'ProviderRoutes'
        $usageSection.Text = & $text 'UsageOverview'
        $syncStatus.Text = ((& $text 'LastSync') -f $QuotaRefreshSeconds)
        $hint.Text = & $text 'Hint'
        $providerNameLabels['official'].Text = & $text 'OfficialButton'
        $providerNameLabels['honknet'].Text = & $text 'HonknetButton'
        $providerNameLabels['deepseek'].Text = & $text 'DeepSeekButton'
        $quotaTitle.Text = & $text 'QuotaTitle'
        $honkaiQuotaTitle.Text = & $text 'HonkaiQuotaTitle'
        $deepseekQuotaTitle.Text = & $text 'DeepSeekQuotaTitle'
        $privacy.Text = & $text 'Privacy'
        & $refresh
        & $renderQuota
        & $renderDeepSeek
        & $renderHonkai
    }

    $languageButton.Add_Click({
        $uiState.Language = if ($uiState.Language -eq 'zh-CN') { 'en' } else { 'zh-CN' }
        & $updateLanguage
    })

    $form.Add_FormClosing({
        $quotaAutoTimer.Stop()
        $quotaPollTimer.Stop()
        $deepseekAutoTimer.Stop()
        $deepseekPollTimer.Stop()
        $honkaiAutoTimer.Stop()
        $honkaiPollTimer.Stop()
        if ($null -ne $quotaState.Process -and -not $quotaState.Process.HasExited) {
            try { $quotaState.Process.Kill() } catch { }
        }
        if ($null -ne $deepseekState.Process -and -not $deepseekState.Process.HasExited) {
            try { $deepseekState.Process.Kill() } catch { }
        }
        if ($null -ne $honkaiState.Process -and -not $honkaiState.Process.HasExited) {
            try { $honkaiState.Process.Kill() } catch { }
        }
    })

    & $updateLanguage
    $quotaPollTimer.Start()
    $deepseekPollTimer.Start()
    $honkaiPollTimer.Start()
    $quotaAutoTimer.Start()
    $deepseekAutoTimer.Start()
    $honkaiAutoTimer.Start()
    & $startQuotaRefresh
    & $startHonkaiRefresh
    & $startDeepSeekRefresh
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
