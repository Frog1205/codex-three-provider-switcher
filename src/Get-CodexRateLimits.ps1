param(
    [switch]$Json,
    [ValidateRange(3, 60)]
    [int]$TimeoutSeconds = 15,
    [string]$NodePath,
    [string]$CodexJsPath
)

$ErrorActionPreference = 'Stop'

function Read-ServerMessage {
    param(
        [Diagnostics.Process]$Process,
        [int]$Seconds
    )

    $task = $Process.StandardOutput.ReadLineAsync()
    if (-not $task.Wait([TimeSpan]::FromSeconds($Seconds))) {
        throw "Timed out waiting for Codex app-server after $Seconds seconds."
    }
    if ($null -eq $task.Result) {
        throw 'Codex app-server exited before returning a complete response.'
    }
    return $task.Result | ConvertFrom-Json
}

if ([string]::IsNullOrWhiteSpace($NodePath)) {
    $bundledNode = Join-Path $env:APPDATA 'npm\node.exe'
    if (Test-Path -LiteralPath $bundledNode) {
        $NodePath = $bundledNode
    }
    else {
        $NodePath = (Get-Command node.exe -ErrorAction Stop).Source
    }
}
if ([string]::IsNullOrWhiteSpace($CodexJsPath)) {
    $CodexJsPath = Join-Path $env:APPDATA 'npm\node_modules\@openai\codex\bin\codex.js'
}
if (-not (Test-Path -LiteralPath $NodePath)) { throw "Node.js was not found: $NodePath" }
if (-not (Test-Path -LiteralPath $CodexJsPath)) {
    throw "Codex CLI was not found: $CodexJsPath. Install or update @openai/codex first."
}

$startInfo = New-Object Diagnostics.ProcessStartInfo
$startInfo.FileName = $NodePath
$startInfo.Arguments = ('"{0}" app-server --stdio -c model_provider=openai' -f $CodexJsPath)
$startInfo.UseShellExecute = $false
$startInfo.RedirectStandardInput = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$startInfo.CreateNoWindow = $true

$process = New-Object Diagnostics.Process
$process.StartInfo = $startInfo
[void]$process.Start()
$stderrTask = $process.StandardError.ReadToEndAsync()

try {
    $initialize = [ordered]@{
        method = 'initialize'
        id = 0
        params = @{
            clientInfo = @{
                name = 'codex_provider_switcher'
                title = 'Codex Provider Switcher'
                version = '2.0.0'
            }
        }
    }
    $process.StandardInput.WriteLine(($initialize | ConvertTo-Json -Compress -Depth 5))
    $process.StandardInput.Flush()

    do { $message = Read-ServerMessage $process $TimeoutSeconds } until ($message.id -eq 0)
    if ($message.error) { throw "Codex app-server initialization failed: $($message.error.message)" }

    $process.StandardInput.WriteLine('{"method":"initialized"}')
    $process.StandardInput.WriteLine('{"method":"account/rateLimits/read","id":6}')
    $process.StandardInput.Flush()

    do { $message = Read-ServerMessage $process $TimeoutSeconds } until ($message.id -eq 6)
    if ($message.error) { throw "Rate-limit query failed: $($message.error.message)" }

    $result = $message.result
    $snapshot = $null
    if ($result.rateLimitsByLimitId -and $result.rateLimitsByLimitId.codex) {
        $snapshot = $result.rateLimitsByLimitId.codex
    }
    elseif ($result.rateLimits -and $result.rateLimits.limitId -eq 'codex') {
        $snapshot = $result.rateLimits
    }
    if ($null -eq $snapshot) { throw 'The Codex rate-limit bucket was not returned.' }

    $windows = @()
    foreach ($windowName in @('primary', 'secondary')) {
        $window = $snapshot.$windowName
        if ($null -ne $window -and $null -ne $window.usedPercent) {
            $remaining = [math]::Max(0, 100 - [double]$window.usedPercent)
            $resetLocal = if ($null -ne $window.resetsAt) {
                [DateTimeOffset]::FromUnixTimeSeconds([long]$window.resetsAt).ToLocalTime().ToString('o')
            }
            else { $null }
            $windows += [pscustomobject]@{
                window = $windowName
                used_percent = [double]$window.usedPercent
                remaining_percent = $remaining
                window_duration_mins = $window.windowDurationMins
                resets_at = $window.resetsAt
                resets_at_local = $resetLocal
            }
        }
    }
    if ($windows.Count -eq 0) { throw 'The Codex rate-limit bucket did not contain a usage window.' }

    $minimum = [double](($windows | Measure-Object remaining_percent -Minimum).Minimum)
    $limitingWindows = @($windows | Where-Object { [double]$_.remaining_percent -eq $minimum })
    $limiting = $limitingWindows |
        Sort-Object @{ Expression = { if ($null -eq $_.resets_at) { 0 } else { [long]$_.resets_at } }; Descending = $true } |
        Select-Object -First 1

    $output = [pscustomobject]@{
        checked_at = [DateTimeOffset]::Now.ToString('o')
        codex_remaining_percent = $minimum
        codex_resets_at = $limiting.resets_at
        codex_resets_at_local = $limiting.resets_at_local
        codex_window_duration_mins = $limiting.window_duration_mins
        plan_type = $snapshot.planType
        rate_limit_reached_type = $snapshot.rateLimitReachedType
        windows = $windows
    }

    if ($Json) {
        $output | ConvertTo-Json -Depth 6 -Compress
    }
    else {
        Write-Output "Codex remaining: $($output.codex_remaining_percent)%"
        Write-Output "Resets at: $($output.codex_resets_at_local)"
        $windows | Format-Table window, used_percent, remaining_percent, window_duration_mins, resets_at_local -AutoSize
    }
}
catch {
    if (-not $process.HasExited) { try { $process.Kill() } catch { } }
    $stderrReady = $stderrTask.Wait(2000)
    $stderr = if ($stderrReady) { $stderrTask.Result } else { '' }
    if ([string]::IsNullOrWhiteSpace($stderr)) { throw }
    throw "$($_.Exception.Message) app-server: $($stderr.Trim())"
}
finally {
    try { $process.StandardInput.Close() } catch { }
    if (-not $process.HasExited) { try { $process.Kill() } catch { } }
    $process.Dispose()
}
