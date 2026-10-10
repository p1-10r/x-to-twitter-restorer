# Change only the Windows user's pinned Twitter Brave shortcut icon.
# Does not modify browser policies, profiles, installed PWAs, or tweets.
[CmdletBinding()]
param(
    [ValidateSet('Big-Blue-Bird', 'White-Circle', 'Blue-Tile')]
    [string]$Style = 'Big-Blue-Bird'
)
$ErrorActionPreference = 'Stop'
$pinFolder = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
$dataFolder = Join-Path $env:LOCALAPPDATA 'TwitterBlueBirdRestorer\TaskbarIcon'
$iconFolder = Join-Path $dataFolder 'icons'
$backupFolder = Join-Path $dataFolder 'backups'
$stateFile = Join-Path $dataFolder 'shortcut-backups.json'
$iconSource = Join-Path $PSScriptRoot ('icons\Twitter-' + $Style + '.ico')
$iconDestination = Join-Path $iconFolder ('Twitter-' + $Style + '.ico')

if (-not (Test-Path -LiteralPath $iconSource)) { throw "Missing icon file: $iconSource" }
if (-not (Test-Path -LiteralPath $pinFolder)) { throw 'Windows pinned taskbar shortcuts folder not found.' }
if (Test-Path -LiteralPath $stateFile) {
    throw 'An icon change is already recorded. Run Undo-Twitter-Taskbar.ps1 before applying another style.'
}

$shell = New-Object -ComObject WScript.Shell
$twitterShortcuts = New-Object 'System.Collections.Generic.List[System.IO.FileInfo]'
foreach ($file in @(Get-ChildItem -LiteralPath $pinFolder -Filter '*.lnk' -File)) {
    if ($file.BaseName -notmatch '^Twitter(?:\s*\(\d+\))?$') { continue }
    $link = $shell.CreateShortcut($file.FullName)
    $target = [string]$link.TargetPath
    if ($target -match '(?i)(?:brave|chrome_proxy)') { $twitterShortcuts.Add($file) }
}
if ($twitterShortcuts.Count -eq 0) {
    throw @'
Pinned Brave Twitter shortcut not found. Keep Twitter pinned on the taskbar,
and try again. For a manual icon change, follow README.txt.
'@
}

New-Item -ItemType Directory -Path $iconFolder -Force | Out-Null
New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null
Copy-Item -LiteralPath $iconSource -Destination $iconDestination -Force
$records = @()
try {
    foreach ($file in $twitterShortcuts) {
        $backup = Join-Path $backupFolder (([guid]::NewGuid().ToString('N')) + '.lnk')
        Copy-Item -LiteralPath $file.FullName -Destination $backup -ErrorAction Stop
        $records += [pscustomobject]@{shortcut = $file.FullName; backup = $backup}
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
    if (Test-Path -LiteralPath $stateFile) { Remove-Item -LiteralPath $stateFile -Force }
    throw
}
Write-Host 'Done. Please sign out of Windows and sign in again if the icon does not refresh.' -ForegroundColor Green
Write-Host 'If the running app still uses its old icon, Brave may be using its own PWA icon rather than the taskbar shortcut icon.'
Write-Host 'You can undo the change with Undo-Twitter-Taskbar.ps1.'
