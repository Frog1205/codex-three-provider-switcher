param([string]$OutputDir = (Join-Path $env:TEMP 'codex-route-gui-smoke-results'))
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$fixtureRoot = Join-Path $env:TEMP ('codex-gui-fixture-' + [guid]::NewGuid().ToString('N'))
$previousAppData = $env:APPDATA
$previousGuiKey = $env:CODEX_GUI_FIXTURE_KEY
try {
    [IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
    [IO.Directory]::CreateDirectory($OutputDir) | Out-Null
    $env:APPDATA = $fixtureRoot
    $env:CODEX_GUI_FIXTURE_KEY = 'environment-gui-fixture'
    $script:mockRequests = @()
    function Invoke-RestMethod {
        param($Method, $Uri, $Headers, $ContentType, $Body, $TimeoutSec)
        $script:mockRequests += [pscustomobject]@{ Uri=$Uri; Authorization=$Headers.Authorization; Body=($Body | ConvertFrom-Json) }
        return [pscustomobject]@{ output_text='OK' }
    }
    $config = Join-Path $fixtureRoot 'config.toml'
    [IO.File]::WriteAllText($config, "model_provider = `"openai`"`r`nmodel = `"offline-fixture`"")
    $sourceRoot = Join-Path $repoRoot 'src'
    $source = [IO.File]::ReadAllText((Join-Path $sourceRoot 'CodexProviderSwitcher.ps1'))
    # Evaluate the release source with only modal loops and network starts replaced.
    # All GUI construction, route refresh, localization and editor guards run unchanged.
    $source = $source.Replace('$PSScriptRoot', ("'" + $sourceRoot.Replace("'", "''") + "'"))
    $source = $source.Replace('    & $startQuotaRefresh', '    # Offline GUI fixture')
    $source = $source.Replace('    & $startHonkaiRefresh', '    # Offline GUI fixture')
    $source = $source.Replace('    & $startDeepSeekRefresh', '    # Offline GUI fixture')
    $dialogCheck = @'
    if ($save.Enabled -or $switch.Enabled) { throw 'Untested routes must not be saved or switched.' }
    if (-not $boxes[5].UseSystemPasswordChar) { throw 'API key field is not masked.' }
    if ($labels[1] -notmatch '线路代号' -or $labels[3] -ne '模型 ID' -or $labels[4] -notmatch '选填') { throw 'Beginner field labels are missing.' }
    $helpText = ($dialog.Controls | Where-Object { $_ -is [Windows.Forms.Label] } | ForEach-Object { $_.Text }) -join ' '
    foreach ($expectedHelp in @('my-api', '真实 model ID', '只读取该变量', 'API Key')) {
        if (-not $helpText.Contains($expectedHelp)) { throw ('Field help missing: ' + $expectedHelp) }
    }
    $boxes[4].Text = 'CODEX_RELEASE_TEST_KEY'
    if ($boxes[5].Enabled) { throw 'Named environment variable must take precedence over direct key entry.' }
    $boxes[4].Text = ''
    if (-not $boxes[5].Enabled) { throw 'Direct API key entry should be available without an environment variable name.' }
    if ($save.Enabled -or $switch.Enabled) { throw 'Credential changes must invalidate the connection test.' }
    foreach ($control in $dialog.Controls) {
        if ($control.Right -gt $dialog.ClientSize.Width -or $control.Bottom -gt $dialog.ClientSize.Height) { throw 'Editor control exceeds dialog bounds.' }
    }
    $dialog.Show()
    [Windows.Forms.Application]::DoEvents()
    $boxes[0].Text='离线测试'; $boxes[1].Text='gui-fixture'; $boxes[2].Text='https://example.invalid/v1'; $boxes[3].Text='vendor/real-model-id'
    $boxes[4].Text='CODEX_GUI_FIXTURE_KEY'; $boxes[5].Text='ignored-gui-fixture'
    $test.PerformClick()
    if (-not $save.Enabled -or $script:mockRequests.Count -ne 1 -or $script:mockRequests[0].Authorization -ne 'Bearer environment-gui-fixture') { throw 'GUI environment-first connection test failed.' }
    if ($script:mockRequests[0].Body.model -ne 'vendor/real-model-id') { throw 'GUI changed the real model ID.' }
    $env:CODEX_GUI_FIXTURE_KEY = $null
    $test.PerformClick()
    if ($save.Enabled -or $switch.Enabled -or $script:mockRequests.Count -ne 1) { throw 'A repeated failed test retained the previous success state.' }
    $env:CODEX_GUI_FIXTURE_KEY = 'environment-gui-fixture'
    $boxes[4].Text='CODEX_GUI_MISSING_' + [guid]::NewGuid().ToString('N')
    $test.PerformClick()
    if ($save.Enabled -or $switch.Enabled -or $script:mockRequests.Count -ne 1) { throw 'GUI missing-variable validation fell back to the direct key or retained test success.' }
    $boxes[4].Text=''; $boxes[5].Text='direct-gui-fixture'
    $test.PerformClick()
    if (-not $save.Enabled -or $script:mockRequests.Count -ne 2 -or $script:mockRequests[1].Authorization -ne 'Bearer direct-gui-fixture') { throw 'GUI direct API key connection test failed.' }
    $boxes[6].SelectedIndex=1
    if ($save.Enabled) { throw 'Changing the protocol did not invalidate the connection test.' }
    $test.PerformClick()
    if ($script:mockRequests.Count -ne 3 -or $script:mockRequests[2].Uri -notmatch '/chat/completions$' -or $script:mockRequests[2].Body.model -ne 'vendor/real-model-id') { throw 'Chat completions request did not preserve the model ID.' }
    foreach ($index in 0..5) { $boxes[$index].Text='' }
    $boxes[6].SelectedIndex=0; $testStatus.Text='尚未测试'
    $dialogBitmap = New-Object Drawing.Bitmap($dialog.Width, $dialog.Height)
    try {
        $dialog.DrawToBitmap($dialogBitmap, [Drawing.Rectangle]::new(0, 0, $dialog.Width, $dialog.Height))
        $dialogBitmap.Save((Join-Path $OutputDir 'custom-editor.png'))
    } finally { $dialogBitmap.Dispose(); $dialog.Dispose() }
    return $false
'@
    $source = $source.Replace('    [void]$dialog.ShowDialog()', $dialogCheck)
    $formCheck = @'
    try {
        if ($form.Text -ne 'Codex API 路由管理器') { throw 'Incorrect product title.' }
        if ($versionLabel.Text -notmatch 'V_1.4_261026.01') { throw 'Incorrect release version.' }
        if ($routeTabs.TabPages.Count -ne 2 -or $customRouteList.Items.Count -ne 3) { throw 'Missing route categories or built-in routes.' }
        if ($null -eq $form.Icon -or -not (Test-Path -LiteralPath $iconPath)) { throw 'Release icon is missing.' }
        $uiState.Language = 'en'
        & $updateLanguage
        if ($form.Text -ne 'Codex API Route Manager' -or $customPage.Text -ne 'Custom endpoints') { throw 'English localization failed.' }
        $uiState.Language = 'zh-CN'
        & $updateLanguage
        $routeTabs.SelectedTab = $customPage
        $form.Show()
        [Windows.Forms.Application]::DoEvents()
        $formBitmap = New-Object Drawing.Bitmap($form.Width, $form.Height)
        try {
            $form.DrawToBitmap($formBitmap, [Drawing.Rectangle]::new(0, 0, $form.Width, $form.Height))
            $formBitmap.Save((Join-Path $OutputDir 'main-window.png'))
        } finally { $formBitmap.Dispose() }
        Show-CustomProviderDialog | Out-Null
        Write-Output 'PASS: real WinForms construction, release title/version/icon, three custom routes, both languages, editor bounds, masked key, and disabled save/switch guards; no network requests.'
    } finally {
        foreach ($timer in @($quotaAutoTimer, $quotaPollTimer, $deepseekAutoTimer, $deepseekPollTimer, $honkaiAutoTimer, $honkaiPollTimer)) { $timer.Stop(); $timer.Dispose() }
        $form.Dispose()
    }
'@
    $source = $source.Replace('    [void]$form.ShowDialog()', $formCheck)
    & ([scriptblock]::Create($source)) -ConfigPath $config -ProvidersPath (Join-Path $sourceRoot 'providers.json') -NoRestart
}
finally {
    $env:APPDATA = $previousAppData
    $env:CODEX_GUI_FIXTURE_KEY = $previousGuiKey
    $absolute = [IO.Path]::GetFullPath($fixtureRoot)
    $tempPrefix = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
    if (-not $absolute.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup path.' }
    Remove-Item -LiteralPath $absolute -Recurse -Force
}
