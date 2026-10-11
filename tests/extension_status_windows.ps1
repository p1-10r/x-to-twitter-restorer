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
[IO.File]::WriteAllText($manifestPath, '{"name":"Twitter Blue Bird Restorer","version":"1.5.11"}', [Text.Encoding]::UTF8)
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
$good = @{extensions=@{settings=@{abc=@{manifest=@{name='Twitter Blue Bird Restorer';version='1.5.11'};state=1;path=$extensionFolder}}}}
$disabled = @{extensions=@{settings=@{abc=@{manifest=@{name='Twitter Blue Bird Restorer';version='1.5.11'};state=0;path=$extensionFolder}}}}
try {
    Test-Case @{} $null $false 'No extensions node'
    Test-Case @{extensions=@{}} $null $false 'No settings node'
    Test-Case @{extensions=@{settings=@{}}} $null $false 'Empty settings'
    Test-Case @{extensions=@{settings=@{abc=@{state=1}}}} $null $false 'Missing extension manifest'
    Test-Case @{extensions=@{settings=@{abc=@{manifest=@{name='Twitter Blue Bird Restorer';version='1.5.11'}}}}} $null $false 'Missing state and missing source path must not be inferred'
    # The user's Brave diagnostic reported the registration correctly but could
    # not tell if the saved state was 0 or missing. Keep those cases separate.
    Test-Case @{extensions=@{settings=@{abc=@{manifest=@{name='Twitter Blue Bird Restorer';version='1.5.11'};path=$extensionFolder}}}} $null $true 'Registered with matching path and missing state is inferred ready'
    $missingStatus = Get-TwitterExtensionStatus -Profile 'Default'
    if (-not $missingStatus.RegistrationPresent -or -not $missingStatus.StateInferred -or $missingStatus.EnabledVerified -or @($missingStatus.StateDetails) -notcontains 'Preferences: missing') {
        throw 'Failed: missing state must be visible in diagnostics.'
    }
    # Missing in one source must not override explicit disabled state in the other.
    $missing = @{extensions=@{settings=@{abc=@{manifest=@{name='Twitter Blue Bird Restorer';version='1.5.11'};path=$extensionFolder}}}}
    Test-Case $missing $disabled $false 'Missing state cannot override explicit disabled'
    Test-Case $disabled $null $false 'Saved state zero is disabled'
    $disabledStatus = Get-TwitterExtensionStatus -Profile 'Default'
    if (-not $disabledStatus.Disabled -or @($disabledStatus.StateDetails) -notcontains 'Preferences: 0') {
        throw 'Failed: saved state zero must be distinguishable from missing.'
    }
    Test-Case $disabled $missing $false 'Explicit disable cannot be overridden by missing state'
    Test-Case $disabled $null $false 'Disabled extension in Preferences'
    Test-Case $good $null $true 'Enabled extension in Preferences'
    $verifiedStatus = Get-TwitterExtensionStatus -Profile 'Default'
    if (-not $verifiedStatus.EnabledVerified -or $verifiedStatus.StateInferred) { throw 'Failed: state=1 must be verified, not inferred.' }
    Test-Case @{extensions=@{}} $good $true 'Enabled extension only in Secure Preferences'
    Test-Case $disabled $good $true 'Secure Preferences enabled, Preferences stale disabled'
    Test-Case $good $disabled $true 'Preferences enabled, Secure Preferences stale disabled'
    Test-Case $null $good $true 'No normal Preferences, only Secure Preferences'
    Test-Case $null $null $false 'Neither preferences file exists'
    Test-Case $good $null $true 'Normal Preferences works without Secure Preferences'
    Test-Case $null $good $true 'Secure Preferences works without normal Preferences'
    Test-Case @{extensions=@{settings=@{abc=@{state=1;path=$extensionFolder}}}} $null $true 'Installed unpacked path without cached manifest'
    Test-Case @{extensions=@{settings=@{abc=@{manifest=@{name='__MSG_appName__';version='1.5.11'};state=1;path=$extensionFolder}}}} $null $true 'Localized browser cached name with matching stable extension path'
    Test-Case @{extensions=@{settings=@{abc=@{manifest=('{"name":"Twitter Blue Bird Restorer","version":"1.5.11"}');state=1;path=$extensionFolder}}}} $null $true 'Manifest cached as JSON string'
    Test-Case @{extensions=@{settings=@{abc=@{manifest=@{name='Not Twitter';version='1.5.11'};state=1;path=$extensionFolder}}}} $null $true 'Cached display name stale but unpacked path matches'
    $oldExtensionFolder = Join-Path $tempRoot 'OldExtension'
    New-Item -ItemType Directory -Path $oldExtensionFolder -Force | Out-Null
    Test-Case @{extensions=@{settings=@{abc=@{manifest=@{name='Twitter Blue Bird Restorer';version='1.5.11'};state=1;path=$oldExtensionFolder}}}} $null $false 'Matching name but old unpacked folder cannot auto-update'
    Test-Case @{extensions=@{settings=@{abc=@{manifest=@{name='Twitter Blue Bird Restorer';version='1.5.11'};path=$oldExtensionFolder}}}} $null $false 'Missing state cannot infer a different source directory'
    Test-Case @{extensions=@{settings=@{abc=@{manifest=@{name='Twitter Blue Bird Restorer';version='1.5.8'};state=1;path=$extensionFolder}}}} $null $false 'Cached old browser manifest requires Reload'
    Test-Case @{extensions=@{settings=@{abc=@{manifest=@{name='Twitter Blue Bird Restorer';version='1.5.8'};path=$extensionFolder}}}} $null $false 'Missing state must not hide stale version'
    Test-Case @{extensions=@{settings=@{abc=@{manifest=@{name='Twitter Blue Bird Restorer';version='1.5.11'};state='oops';path=$extensionFolder}}}} $null $false 'Unrecognized state cannot be inferred'

    $alternate = Join-Path $tempRoot 'Profile 1'
    New-Item -ItemType Directory -Path $alternate -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $alternate 'Secure Preferences'), ($good | ConvertTo-Json -Depth 20), [Text.Encoding]::UTF8)
    $foundProfiles = @(Get-TwitterEnabledProfiles)
    if ($foundProfiles.Count -lt 1 -or @($foundProfiles | Where-Object { $_.Profile -eq 'Profile 1' }).Count -ne 1) { throw 'Failed: other profile is not detected.' }
    Remove-Item -LiteralPath (Join-Path $alternate 'Secure Preferences') -Force

    Write-Host 'PASS: 28 Chromium extension registration checks including multiple profiles' -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $tempRoot -Force -Recurse -ErrorAction SilentlyContinue
}
