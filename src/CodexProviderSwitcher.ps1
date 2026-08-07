param(
    [ValidateSet('gui', 'official', 'gpt', 'honkai', 'honknet', 'deepseek', 'ds', 'status')]
    [string]$Mode = 'gui',
    [string]$ConfigPath = (Join-Path $env:USERPROFILE '.codex\config.toml'),
    [string]$ProvidersPath = (Join-Path $PSScriptRoot 'providers.json'),
    [string]$RateLimitsPath = (Join-Path $PSScriptRoot 'Get-CodexRateLimits.ps1'),
    [ValidateRange(15, 3600)]
    [int]$QuotaRefreshSeconds = 60,
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
    $form = New-Object Windows.Forms.Form
    $form.Text = 'Codex Three-Provider Switcher'
    $form.ClientSize = New-Object Drawing.Size(680, 500)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.Font = New-Object Drawing.Font('Microsoft YaHei UI', 10)

    $title = New-Object Windows.Forms.Label
    $title.Text = 'Codex Provider Switcher'
    $title.Font = New-Object Drawing.Font('Microsoft YaHei UI', 19, [Drawing.FontStyle]::Bold)
    $title.AutoSize = $true
    $title.Location = New-Object Drawing.Point(30, 24)
    $form.Controls.Add($title)

    $status = New-Object Windows.Forms.Label
    $status.AutoSize = $true
    $status.Location = New-Object Drawing.Point(33, 78)
    $form.Controls.Add($status)

    $hint = New-Object Windows.Forms.Label
    $hint.Text = "Save the current task before switching.`r`nCreate a new task after Codex restarts."
    $hint.Size = New-Object Drawing.Size(610, 44)
    $hint.Location = New-Object Drawing.Point(33, 112)
    $form.Controls.Add($hint)

    $buttonSpecs = @(
        @{ Text = $definitions.official.display_name; Provider = 'official'; X = 33; Color = [Drawing.Color]::FromArgb(16, 163, 127) },
        @{ Text = $definitions.honknet.display_name; Provider = 'honknet'; X = 251; Color = [Drawing.Color]::FromArgb(37, 99, 235) },
        @{ Text = $definitions.deepseek.display_name; Provider = 'deepseek'; X = 469; Color = [Drawing.Color]::FromArgb(109, 40, 217) }
    )

    $refresh = {
        $state = Get-CurrentState
        $status.Text = "Current provider: $($state.Display)    Model: $($state.Model)"
        $honkReady = Get-KeyPresent ([string]$definitions.honknet.env_key)
        $dsReady = Get-KeyPresent ([string]$definitions.deepseek.env_key)
        $catalogReady = Test-Catalog $definitions.deepseek
        $health.Text = "Honknet Key: $(if ($honkReady) {'Ready'} else {'Missing'})    DeepSeek Key: $(if ($dsReady) {'Ready'} else {'Missing'})    Catalog: $(if ($catalogReady) {'Ready'} else {'Missing'})"
        $health.ForeColor = if ($honkReady -and $dsReady -and $catalogReady) { [Drawing.Color]::ForestGreen } else { [Drawing.Color]::Firebrick }
    }

    foreach ($spec in $buttonSpecs) {
        $button = New-Object Windows.Forms.Button
        $button.Text = $spec.Text
        $button.Tag = $spec.Provider
        $button.Size = New-Object Drawing.Size(178, 62)
        $button.Location = New-Object Drawing.Point($spec.X, 160)
        $button.BackColor = $spec.Color
        $button.ForeColor = [Drawing.Color]::White
        $button.FlatStyle = 'Flat'
        $button.Add_Click({
            try {
                if (Set-CodexProvider ([string]$this.Tag) $true) {
                    & $refresh
                    [Windows.Forms.MessageBox]::Show('Switch complete. Create a new task in Codex.', 'Done', 'OK', 'Information') | Out-Null
                }
            }
            catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Switch failed', 'OK', 'Error') | Out-Null }
        })
        $form.Controls.Add($button)
    }

    $health = New-Object Windows.Forms.Label
    $health.AutoSize = $false
    $health.Size = New-Object Drawing.Size(610, 38)
    $health.Location = New-Object Drawing.Point(33, 244)
    $form.Controls.Add($health)

    $quotaTitle = New-Object Windows.Forms.Label
    $quotaTitle.Text = 'Official Codex quota'
    $quotaTitle.Font = New-Object Drawing.Font('Microsoft YaHei UI', 12, [Drawing.FontStyle]::Bold)
    $quotaTitle.AutoSize = $true
    $quotaTitle.Location = New-Object Drawing.Point(33, 286)
    $form.Controls.Add($quotaTitle)

    $refreshQuotaButton = New-Object Windows.Forms.Button
    $refreshQuotaButton.Text = 'Refresh'
    $refreshQuotaButton.Size = New-Object Drawing.Size(88, 32)
    $refreshQuotaButton.Location = New-Object Drawing.Point(559, 280)
    $form.Controls.Add($refreshQuotaButton)

    $quotaPercent = New-Object Windows.Forms.Label
    $quotaPercent.Text = 'Official Codex remaining: Checking...'
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
    $quotaReset.Text = 'Resets: Waiting for official account data'
    $quotaReset.AutoSize = $true
    $quotaReset.Location = New-Object Drawing.Point(33, 382)
    $form.Controls.Add($quotaReset)

    $quotaStatus = New-Object Windows.Forms.Label
    $quotaStatus.Text = "Auto refresh: every $QuotaRefreshSeconds seconds"
    $quotaStatus.AutoSize = $false
    $quotaStatus.Size = New-Object Drawing.Size(614, 34)
    $quotaStatus.Location = New-Object Drawing.Point(33, 412)
    $quotaStatus.ForeColor = [Drawing.Color]::DimGray
    $form.Controls.Add($quotaStatus)

    $privacy = New-Object Windows.Forms.Label
    $privacy.Text = 'Keys come only from Windows environment variables. Config is backed up.'
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
    }

    $showQuotaError = {
        param([string]$Message)
        $quotaPercent.Text = 'Official Codex remaining: Unavailable'
        $quotaPercent.ForeColor = [Drawing.Color]::Firebrick
        $quotaFill.Width = 1
        $quotaFill.BackColor = [Drawing.Color]::Firebrick
        $quotaReset.Text = 'Resets: Unknown'
        $quotaStatus.Text = "$Message`r`nThe provider switcher remains available."
        $quotaStatus.ForeColor = [Drawing.Color]::Firebrick
    }

    $applyQuotaJson = {
        param([string]$Text)
        try {
            $data = $Text | ConvertFrom-Json
            $remaining = [math]::Max(0, [math]::Min(100, [double]$data.codex_remaining_percent))
            $quotaPercent.Text = ('Official Codex remaining: {0:0.#}%' -f $remaining)
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

            if (-not [string]::IsNullOrWhiteSpace([string]$data.codex_resets_at_local)) {
                $reset = [DateTimeOffset]::Parse([string]$data.codex_resets_at_local).ToLocalTime()
                $quotaReset.Text = "Resets: $($reset.ToString('yyyy-MM-dd HH:mm'))"
            }
            else {
                $quotaReset.Text = 'Resets: Not reported'
            }

            $checked = [DateTimeOffset]::Parse([string]$data.checked_at).ToLocalTime()
            $current = Get-CurrentState
            if ($current.Provider -ne 'openai' -and $remaining -gt 0) {
                $quotaStatus.Text = "Official quota is available. You can switch back to GPT Official.`r`nUpdated $($checked.ToString('HH:mm:ss')); auto refresh every $QuotaRefreshSeconds seconds."
                $quotaStatus.ForeColor = [Drawing.Color]::ForestGreen
            }
            elseif ($remaining -le 0) {
                $quotaStatus.Text = "Official quota is exhausted. Keep using a relay until reset.`r`nUpdated $($checked.ToString('HH:mm:ss')); auto refresh every $QuotaRefreshSeconds seconds."
                $quotaStatus.ForeColor = [Drawing.Color]::Firebrick
            }
            else {
                $quotaStatus.Text = "Official quota is available.`r`nUpdated $($checked.ToString('HH:mm:ss')); auto refresh every $QuotaRefreshSeconds seconds."
                $quotaStatus.ForeColor = [Drawing.Color]::ForestGreen
            }

            if ($null -ne $quotaState.LastRemaining -and [double]$quotaState.LastRemaining -le 0 -and $remaining -gt 0) {
                [System.Media.SystemSounds]::Asterisk.Play()
            }
            $quotaState.LastRemaining = $remaining
        }
        catch {
            & $showQuotaError "Quota response could not be parsed: $($_.Exception.Message)"
        }
    }

    $startQuotaRefresh = {
        if ($null -ne $quotaState.Process -and -not $quotaState.Process.HasExited) { return }
        if (-not (Test-Path -LiteralPath $RateLimitsPath)) {
            & $showQuotaError "Quota reader not found: $RateLimitsPath"
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
        $refreshQuotaButton.Enabled = $false
        $refreshQuotaButton.Text = 'Checking...'
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
            $refreshQuotaButton.Text = 'Refresh'
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
        $refreshQuotaButton.Text = 'Refresh'

        if ($quotaState.TimedOut) {
            & $showQuotaError 'Official quota check timed out.'
        }
        elseif ($exitCode -ne 0 -or [string]::IsNullOrWhiteSpace($stdout)) {
            $detail = if ([string]::IsNullOrWhiteSpace($stderr)) { 'No data returned.' } else { $stderr.Trim() }
            & $showQuotaError "Official quota check failed: $detail"
        }
        else {
            & $applyQuotaJson $stdout
        }
    })

    $quotaAutoTimer = New-Object Windows.Forms.Timer
    $quotaAutoTimer.Interval = $QuotaRefreshSeconds * 1000
    $quotaAutoTimer.Add_Tick({ & $startQuotaRefresh })
    $refreshQuotaButton.Add_Click({ & $startQuotaRefresh })

    $form.Add_FormClosing({
        $quotaAutoTimer.Stop()
        $quotaPollTimer.Stop()
        if ($null -ne $quotaState.Process -and -not $quotaState.Process.HasExited) {
            try { $quotaState.Process.Kill() } catch { }
        }
    })

    & $refresh
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
