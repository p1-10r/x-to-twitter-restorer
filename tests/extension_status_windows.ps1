# Run on Windows with: powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\extension_status_windows.ps1
# Synthetic Chromium profile, no edits to the user's browser profile.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'scripts\Twitter.Common.ps1')
$tempRoot = Join-Path $env:TEMP ('twitter-status-test-' + [guid]::NewGuid().ToString('N'))
$profileDir = Join-Path $tempRoot 'Default'
$extensionFolder = Join-Path $tempRoot 'Extension'
New-Item -ItemType Directory -Path $profileDir,$extensionFolder -Force | Out-Null
function Get-BrowserProfileRoot { return $tempRoot }
$script:SelectedBrowser = Get-BrowserDefinition 'brave'
$script:ExtensionRoot = $extensionFolder
$manifestPath = Join-Path $extensionFolder 'manifest.json'
[IO.File]::WriteAllText($manifestPath, '{"name":"Twitter Blue Bird Restorer","version":"1.5.6"}', [Text.Encoding]::UTF8)
$preferencesPath = Join-Path $profileDir 'Preferences'
$securePath = Join-Path $profileDir 'Secure Preferences'
function Test-Case([object]$Prefs,[object]$Secure,[bool]$ExpectedInstalled,[string]$Label) {
    if ($null -eq $Prefs) { Remove-Item -LiteralPath $preferencesPath -ErrorAction SilentlyContinue }
    else { [IO.File]::WriteAllText($preferencesPath, ($Prefs | ConvertTo-Json -Depth 20), [Text.Encoding]::UTF8) }
    if ($null -eq $Secure) { Remove-Item -LiteralPath $securePath -ErrorAction SilentlyContinue }
    else { [IO.File]::WriteAllText($securePath, ($Secure | ConvertTo-Json -Depth 20), [Text.Encoding]::UTF8) }
    $status = Get-TwitterExtensionStatus -Profile 'Default'
    if ([bool]$status.Installed -ne $ExpectedInstalled) { throw ('Failed: ' + $Label + ' : ' + $status.Reason) }
}
$good = @{extensions=@{settings=@{abc=@{manifest=@{name='Twitter Blue Bird Restorer';version='1.5.6'};state=1;path=$extensionFolder}}}}
$disabled = @{extensions=@{settings=@{abc=@{manifest=@{name='Twitter Blue Bird Restorer';version='1.5.6'};state=0;path=$extensionFolder}}}}
try {
    Test-Case @{} $null $false 'No extensions node'
    Test-Case @{extensions=@{}} $null $false 'No settings node'
    Test-Case @{extensions=@{settings=@{}}} $null $false 'Empty settings'
    Test-Case @{extensions=@{settings=@{abc=@{state=1}}}} $null $false 'Missing extension manifest'
    Test-Case @{extensions=@{settings=@{abc=@{manifest=@{name='Twitter Blue Bird Restorer';version='1.5.6'}}}}} $null $false 'Missing state'
    Test-Case $disabled $null $false 'Disabled extension in Preferences'
    Test-Case $good $null $true 'Enabled extension in Preferences'
    Test-Case @{extensions=@{}} $good $true 'Enabled extension only in Secure Preferences'
    Test-Case $disabled $good $true 'Secure Preferences enabled, Preferences stale disabled'
    Test-Case $good $disabled $true 'Preferences enabled, Secure Preferences stale disabled'
    Test-Case $null $good $true 'No normal Preferences, only Secure Preferences'
    Test-Case $null $null $false 'Neither preferences file exists'
    Test-Case $good $null $true 'Normal Preferences works without Secure Preferences'
    Test-Case $null $good $true 'Secure Preferences works without normal Preferences'
    Test-Case @{extensions=@{settings=@{abc=@{state=1;path=$extensionFolder}}}} $null $true 'Installed unpacked path without cached manifest'
    $alternate = Join-Path $tempRoot 'Profile 1'
    New-Item -ItemType Directory -Path $alternate -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $alternate 'Secure Preferences'), ($good | ConvertTo-Json -Depth 20), [Text.Encoding]::UTF8)
    $foundProfiles = @(Get-TwitterEnabledProfiles)
    if ($foundProfiles.Count -lt 1 -or @($foundProfiles | Where-Object { $_.Profile -eq 'Profile 1' }).Count -ne 1) { throw 'Failed: other profile is not detected.' }
    Remove-Item -LiteralPath (Join-Path $alternate 'Secure Preferences') -Force

    Write-Host 'PASS: 16 Chromium extension registration checks including multiple profiles' -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $tempRoot -Force -Recurse -ErrorAction SilentlyContinue
}
