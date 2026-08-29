param(
    [switch]$Json,
    [ValidateRange(3, 60)]
    [int]$TimeoutSeconds = 15,
    [string]$ApiKey,
    [string]$BaseUrl
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = `
    [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    foreach ($scope in @('Process', 'User', 'Machine')) {
        $candidate = [Environment]::GetEnvironmentVariable('DEEPSEEK_API_KEY', $scope)
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $ApiKey = $candidate
            break
        }
    }
}

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    throw 'DEEPSEEK_API_KEY is missing. Configure it in Windows user environment variables first.'
}

if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
    $BaseUrl = 'https://api.deepseek.com'
}

$headers = @{
    Authorization = "Bearer $ApiKey"
    Accept = 'application/json'
}
$uri = $BaseUrl.TrimEnd('/') + '/user/balance'

try {
    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -TimeoutSec $TimeoutSeconds
}
catch {
    $status = if ($null -ne $_.Exception.Response) {
        try { [int]$_.Exception.Response.StatusCode } catch { $null }
    }
    else { $null }
    if ($null -ne $status) {
        throw "DeepSeek balance query failed with HTTP $status."
    }
    throw "DeepSeek balance query failed: $($_.Exception.Message)"
}

$entries = @()
foreach ($info in @($response.balance_infos)) {
    $entries += [pscustomobject]@{
        currency = [string]$info.currency
        total_balance = [decimal]::Parse([string]$info.total_balance, [Globalization.CultureInfo]::InvariantCulture)
        granted_balance = [decimal]::Parse([string]$info.granted_balance, [Globalization.CultureInfo]::InvariantCulture)
        topped_up_balance = [decimal]::Parse([string]$info.topped_up_balance, [Globalization.CultureInfo]::InvariantCulture)
    }
}

if ($entries.Count -eq 0) {
    throw 'The DeepSeek balance response did not contain balance_infos.'
}

$preferred = @($entries | Where-Object { $_.currency -eq 'CNY' } | Select-Object -First 1)
if ($null -eq $preferred) {
    $preferred = @($entries | Where-Object { $_.currency -eq 'USD' } | Select-Object -First 1)
}
if ($null -eq $preferred) {
    $preferred = $entries[0]
}

$output = [pscustomobject]@{
    checked_at = [DateTimeOffset]::Now.ToString('o')
    is_available = [bool]$response.is_available
    currency = $preferred.currency
    total_balance = $preferred.total_balance
    granted_balance = $preferred.granted_balance
    topped_up_balance = $preferred.topped_up_balance
    balance_infos = $entries
    source = 'https://api.deepseek.com/user/balance'
}

if ($Json) {
    $output | ConvertTo-Json -Depth 6 -Compress
}
else {
    Write-Output ("DeepSeek balance: {0:N2} {1}" -f $output.total_balance, $output.currency)
    Write-Output ("Available: {0}" -f $output.is_available)
    Write-Output ("Topped up: {0:N2} {1}" -f $output.topped_up_balance, $output.currency)
    Write-Output ("Granted: {0:N2} {1}" -f $output.granted_balance, $output.currency)
    $entries | Format-Table currency, total_balance, granted_balance, topped_up_balance -AutoSize
}
