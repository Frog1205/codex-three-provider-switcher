param([string]$OutputDir = (Join-Path $env:TEMP 'codex-route-gui-smoke-results'))
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$fixtureRoot = Join-Path $env:TEMP ('codex-gui-fixture-' + [guid]::NewGuid().ToString('N'))
$previousAppData = $env:APPDATA
try {
    [IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
    [IO.Directory]::CreateDirectory($OutputDir) | Out-Null
    $env:APPDATA = $fixtureRoot
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
    foreach ($control in $dialog.Controls) {
        if ($control.Right -gt $dialog.ClientSize.Width -or $control.Bottom -gt $dialog.ClientSize.Height) { throw 'Editor control exceeds dialog bounds.' }
    }
    $dialog.Show()
    [Windows.Forms.Application]::DoEvents()
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
        if ($versionLabel.Text -notmatch 'V_1.4_261025.01') { throw 'Incorrect release version.' }
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
    $absolute = [IO.Path]::GetFullPath($fixtureRoot)
    $tempPrefix = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
    if (-not $absolute.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup path.' }
    Remove-Item -LiteralPath $absolute -Recurse -Force
}
