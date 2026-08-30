param(
    [switch]$Json,
    [ValidateRange(3, 60)]
    [int]$TimeoutSeconds = 15,
    [string]$ApiKey,
    [string]$BaseUrl,
    [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
    [string]$StartDate,
    [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
    [string]$EndDate,
    [string]$Timezone = 'Asia/Shanghai'
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = `
    [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    foreach ($envName in @('HONKNET_API_KEY', 'HONKAI_API_KEY')) {
        foreach ($scope in @('Process', 'User', 'Machine')) {
            $candidate = [Environment]::GetEnvironmentVariable($envName, $scope)
            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                $ApiKey = $candidate
                break
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($ApiKey)) { break }
    }
}

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    throw 'HONKNET_API_KEY or HONKAI_API_KEY is missing. Configure one in Windows user environment variables first.'
}

if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
    $BaseUrl = 'https://ai.honknet.io'
}

if ([string]::IsNullOrWhiteSpace($StartDate)) {
    $StartDate = (Get-Date).Date.AddDays(1 - (Get-Date).Day).ToString('yyyy-MM-dd')
}
if ([string]::IsNullOrWhiteSpace($EndDate)) {
    $EndDate = Get-Date -Format 'yyyy-MM-dd'
}
$parsedStart = [datetime]::ParseExact($StartDate, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
$parsedEnd = [datetime]::ParseExact($EndDate, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
if ($parsedEnd -lt $parsedStart) {
    throw 'EndDate cannot be earlier than StartDate.'
}

function ConvertTo-HonkaiDecimal {
    param([object]$Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return [decimal]::Zero }
    try {
        return [decimal]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        return [decimal]::Zero
    }
}

function ConvertTo-HonkaiLong {
    param([object]$Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return [long]0 }
    try {
        return [long]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        return [long]0
    }
}

$headers = @{
    Authorization = "Bearer $ApiKey"
    Accept = 'application/json'
}
$query = 'start_date=' + [Uri]::EscapeDataString($StartDate) + `
    '&end_date=' + [Uri]::EscapeDataString($EndDate) + `
    '&timezone=' + [Uri]::EscapeDataString($Timezone)
$uri = $BaseUrl.TrimEnd('/') + '/api/v1/usage?' + $query

try {
    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -TimeoutSec $TimeoutSeconds
}
catch {
    $status = if ($null -ne $_.Exception.Response) {
        try { [int]$_.Exception.Response.StatusCode } catch { $null }
    }
    else { $null }
    if ($null -ne $status) {
        throw "Honknet usage query failed with HTTP $status."
    }
    throw "Honknet usage query failed: $($_.Exception.Message)"
}

$quota = @($response.quota | Select-Object -First 1)
$usage = @($response.usage | Select-Object -First 1)
$plan = @($response.plan | Select-Object -First 1)
$today = if ($null -ne $usage) { @($usage.today | Select-Object -First 1) } else { $null }
$total = if ($null -ne $usage) { @($usage.total | Select-Object -First 1) } else { $null }

$output = [pscustomobject]@{
    checked_at = [DateTimeOffset]::Now.ToString('o')
    valid = [bool]$response.valid
    mode = [string]$response.mode
    status = [string]$response.status
    plan_name = [string]$plan.name
    plan_expires_at = [string]$plan.expires_at
    currency = if ([string]::IsNullOrWhiteSpace([string]$quota.unit)) { 'USD' } else { [string]$quota.unit }
    remaining = ConvertTo-HonkaiDecimal $quota.remaining_usd
    daily_limit = ConvertTo-HonkaiDecimal $quota.daily.limit_usd
    daily_used = ConvertTo-HonkaiDecimal $quota.daily.used_usd
    daily_remaining = ConvertTo-HonkaiDecimal $quota.daily.remaining_usd
    weekly_limit = ConvertTo-HonkaiDecimal $quota.weekly.limit_usd
    weekly_used = ConvertTo-HonkaiDecimal $quota.weekly.used_usd
    weekly_remaining = ConvertTo-HonkaiDecimal $quota.weekly.remaining_usd
    monthly_limit = ConvertTo-HonkaiDecimal $quota.monthly.limit_usd
    monthly_used = ConvertTo-HonkaiDecimal $quota.monthly.used_usd
    monthly_remaining = ConvertTo-HonkaiDecimal $quota.monthly.remaining_usd
    today_requests = ConvertTo-HonkaiLong $today.requests
    today_input_tokens = ConvertTo-HonkaiLong $today.input_tokens
    today_output_tokens = ConvertTo-HonkaiLong $today.output_tokens
    today_cache_read_tokens = ConvertTo-HonkaiLong $today.cache_read_tokens
    today_total_tokens = ConvertTo-HonkaiLong $today.total_tokens
    today_cost_usd = ConvertTo-HonkaiDecimal $today.cost_usd
    period_requests = ConvertTo-HonkaiLong $total.requests
    period_input_tokens = ConvertTo-HonkaiLong $total.input_tokens
    period_output_tokens = ConvertTo-HonkaiLong $total.output_tokens
    period_cache_read_tokens = ConvertTo-HonkaiLong $total.cache_read_tokens
    period_total_tokens = ConvertTo-HonkaiLong $total.total_tokens
    period_cost_usd = ConvertTo-HonkaiDecimal $total.cost_usd
    start_date = $StartDate
    end_date = $EndDate
    timezone = $Timezone
    source = $uri
}

if ($Json) {
    $output | ConvertTo-Json -Depth 5 -Compress
}
else {
    Write-Output ("Honknet usage: {0:N2} {1} remaining" -f $output.remaining, $output.currency)
    Write-Output ("Plan: {0}  Expires: {1}" -f $output.plan_name, $output.plan_expires_at)
    Write-Output ("Today: {0:N0} requests, {1:N0} tokens, {2:N2} {3}" -f `
        $output.today_requests, $output.today_total_tokens, $output.today_cost_usd, $output.currency)
    Write-Output ("Period {0} to {1}: {2:N0} requests, {3:N0} tokens, {4:N2} {5}" -f `
        $output.start_date, $output.end_date, $output.period_requests, $output.period_total_tokens, `
        $output.period_cost_usd, $output.currency)
}