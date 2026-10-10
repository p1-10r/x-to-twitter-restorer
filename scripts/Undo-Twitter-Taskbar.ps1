[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$pinFolder = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
$dataFolder = Join-Path $env:LOCALAPPDATA 'TwitterBlueBirdRestorer\TaskbarIcon'
$stateFile = Join-Path $dataFolder 'shortcut-backups.json'
if (-not (Test-Path -LiteralPath $stateFile)) {
    Write-Host 'No previous taskbar icon change was recorded.'
    return
}
$state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
$records = @($state.shortcuts)
foreach ($record in $records) {
    $expectedFolder = [IO.Path]::GetFullPath($pinFolder).TrimEnd('\')
    $actualFolder = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath([string]$record.shortcut))
    if (-not [string]::Equals($expectedFolder, $actualFolder, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Backup record has an unexpected destination. No changes were made.'
    }
    $backupRoot = [IO.Path]::GetFullPath((Join-Path $dataFolder 'backups')).TrimEnd('\') + '\'
    if (-not [IO.Path]::GetFullPath([string]$record.backup).StartsWith($backupRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Backup record has an unexpected backup source. No changes were made.'
    }
    if (-not (Test-Path -LiteralPath ([string]$record.backup))) {
        throw 'A shortcut backup is missing. No changes were made.'
    }
}
foreach ($record in $records) {
    Copy-Item -LiteralPath ([string]$record.backup) -Destination ([string]$record.shortcut) -Force
    Write-Host ('Restored: ' + [IO.Path]::GetFileName([string]$record.shortcut)) -ForegroundColor Green
}
Remove-Item -LiteralPath $stateFile -Force
Write-Host 'Original shortcut icons restored. Sign out and in again if Windows cached an older icon.'
