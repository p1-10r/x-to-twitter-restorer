# Change only the Windows user's pinned Twitter shortcut for the selected browser icon.
# Does not modify browser policies, profiles, installed PWAs, or tweets.
[CmdletBinding()]
param(
    [ValidateSet('Big-Blue-Bird', 'White-Circle', 'Blue-Tile')]
    [string]$Style = 'Big-Blue-Bird',
    [ValidateSet('Auto','Brave','Chrome','Edge')][string]$Browser = 'Auto'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Twitter.Common.ps1')
$selected = Select-TwitterBrowser -Requested $Browser
Initialize-TwitterBrowser $selected
$pinFolder = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
$dataFolder = Join-Path $env:LOCALAPPDATA 'TwitterBlueBirdRestorer\TaskbarIcon'
$iconFolder = Join-Path $dataFolder 'icons'
$backupFolder = Join-Path $dataFolder 'backups'
$stateFile = Join-Path $dataFolder ('shortcut-backups-' + $selected.Id + '.json')
$iconSource = Join-Path $PSScriptRoot ('icons\Twitter-' + $Style + '.ico')
$iconDestination = Join-Path $iconFolder ('Twitter-' + $Style + '-v1.5.10.ico')

if (-not (Test-Path -LiteralPath $iconSource)) { throw "Missing icon file: $iconSource" }
if (-not (Test-Path -LiteralPath $pinFolder)) { throw 'Windows pinned taskbar shortcuts folder not found.' }
$previousState = $null
if (Test-Path -LiteralPath $stateFile) {
    $previousState = Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-Host 'Updating a previously managed taskbar icon; existing undo backups are preserved.' -ForegroundColor Yellow
}

$shell = New-Object -ComObject WScript.Shell
$twitterShortcuts = New-Object 'System.Collections.Generic.List[System.IO.FileInfo]'
foreach ($file in @(Get-ChildItem -LiteralPath $pinFolder -Filter '*.lnk' -File)) {
    if ($file.BaseName -notmatch '(?i)^Twitter(?:\s*\([^)]+\))?$') { continue }
    $link = $shell.CreateShortcut($file.FullName)
    $target = [string]$link.TargetPath
    if ($target -match $selected.AppPathMatch) { $twitterShortcuts.Add($file) }
}
if ($twitterShortcuts.Count -eq 0) {
    throw @'
Pinned Twitter shortcut for the selected browser not found. Keep Twitter pinned on the taskbar,
and try again. For a manual icon change, follow README.txt.
'@
}

New-Item -ItemType Directory -Path $iconFolder -Force | Out-Null
New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null
Copy-Item -LiteralPath $iconSource -Destination $iconDestination -Force
$records = @()
try {
    foreach ($file in $twitterShortcuts) {
        $existingBackup = $null
        if ($previousState) {
            $existingBackup = @($previousState.shortcuts | Where-Object { $_.shortcut -ceq $file.FullName } | Select-Object -First 1)
        }
        if ($existingBackup -and $existingBackup.Count -gt 0 -and (Test-Path -LiteralPath $existingBackup[0].backup)) {
            $records += $existingBackup[0]
        } else {
            $backup = Join-Path $backupFolder (([guid]::NewGuid().ToString('N')) + '.lnk')
            Copy-Item -LiteralPath $file.FullName -Destination $backup -ErrorAction Stop
            $records += [pscustomobject]@{shortcut = $file.FullName; backup = $backup}
        }
    }
    # Record all backups before changing any shortcut so an interrupted run is recoverable.
    [pscustomobject]@{
        icon = $iconDestination
        createdAt = (Get-Date).ToString('o')
        shortcuts = @($records)
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $stateFile -Encoding UTF8
    foreach ($file in $twitterShortcuts) {
        $link = $shell.CreateShortcut($file.FullName)
        $link.IconLocation = ($iconDestination + ',0')
        $link.Save()
        Write-Host ('Changed pinned icon: ' + $file.Name) -ForegroundColor Green
    }
} catch {
    foreach ($record in $records) {
        if (Test-Path -LiteralPath $record.backup) {
            Copy-Item -LiteralPath $record.backup -Destination $record.shortcut -Force
        }
    }
    if ($previousState) { $previousState | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $stateFile -Encoding UTF8 }
    elseif (Test-Path -LiteralPath $stateFile) { Remove-Item -LiteralPath $stateFile -Force }
    throw
}
Write-Host 'Done. Please sign out of Windows and sign in again if the icon does not refresh.' -ForegroundColor Green
Write-Host 'If the running app still uses its old icon, the browser may be using its own PWA icon rather than the taskbar shortcut icon.'
Write-Host 'You can undo the change with Undo-Twitter-Taskbar.ps1.'
