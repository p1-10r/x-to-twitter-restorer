# Run on Windows with: powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\extension_status_windows.ps1
# Exercises missing Chromium preference keys under StrictMode without touching the real profile.
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
[IO.File]::WriteAllText($manifestPath, '{"name":"Twitter Blue Bird Restorer","version":"1.5.4"}', [Text.Encoding]::UTF8)
$preferencesPath = Join-Path $profileDir 'Preferences'
function Test-Case([object]$Object,[bool]$ExpectedInstalled,[string]$Label) {
    [IO.File]::WriteAllText($preferencesPath, ($Object | ConvertTo-Json -Depth 20), [Text.Encoding]::UTF8)
    $status = Get-TwitterExtensionStatus -Profile 'Default'
    if ([bool]$status.Installed -ne $ExpectedInstalled) { throw ('Failed: ' + $Label + ' : ' + $status.Reason) }
}
try {
    Test-Case @{} $false 'No extensions node'
    Test-Case @{extensions=@{}} $false 'No settings node'
    Test-Case @{extensions=@{settings=@{}}} $false 'Empty settings'
    Test-Case @{extensions=@{settings=@{abc=@{state=1}}}} $false 'Missing extension manifest'
    Test-Case @{extensions=@{settings=@{abc=@{manifest=@{name='Twitter Blue Bird Restorer';version='1.5.4'}}}}} $false 'Missing state'
    Test-Case @{extensions=@{settings=@{abc=@{manifest=@{name='Twitter Blue Bird Restorer';version='1.5.4'};state=0}}}} $false 'Disabled extension'
    Test-Case @{extensions=@{settings=@{abc=@{manifest=@{name='Twitter Blue Bird Restorer';version='1.5.4'};state=1;path=$extensionFolder}}}} $true 'Enabled extension'
    Write-Host 'PASS: 7 Chromium preferences registration fixtures' -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $tempRoot -Force -Recurse -ErrorAction SilentlyContinue
}
