# Windows PowerShell 5.1 integration test, writes only inside a disposable temp folder.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'scripts\Twitter.Common.ps1')
$tempFolder = Join-Path $env:TEMP ('twitter-desktop-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempFolder -Force | Out-Null
$script:DataRoot = Join-Path $tempFolder 'KitData'
$script:SelectedBrowser = Get-BrowserDefinition 'brave'
$shell = New-Object -ComObject WScript.Shell
function New-SyntheticShortcut([string]$Name,[string]$Arguments,[string]$Executable) {
    $file = Join-Path $tempFolder ($Name + '.lnk')
    $shortcut = $shell.CreateShortcut($file)
    $shortcut.TargetPath = $Executable
    $shortcut.Arguments = $Arguments
    $shortcut.IconLocation = 'C:\Windows\System32\shell32.dll,0'
    $shortcut.Save()
    return $file
}
try {
    $exe = 'C:\Program Files\BraveSoftware\Brave-Browser\Application\brave_proxy.exe'
    $matching = New-SyntheticShortcut -Name 'Twitter' -Arguments '--profile-directory=Default --app-id=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' -Executable $exe
    $unrelated = New-SyntheticShortcut -Name 'Twitter (normal browser)' -Arguments 'https://x.com/' -Executable $exe
    $wrongBrowser = New-SyntheticShortcut -Name 'Twitter (Edge)' -Arguments '--app-id=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' -Executable 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge_proxy.exe'
    $found = @(Get-TwitterDesktopLinks -Folders @($tempFolder))
    if ($found.Count -ne 1 -or $found[0].FullName -ne $matching) { throw 'Failed: PWA link matching leaked to unrelated shortcut.' }
    $changed = Repair-TwitterDesktopIcons -Folders @($tempFolder)
    if ($changed -ne 1) { throw 'Failed: expected exactly one repaired PWA link.' }
    $fixed = $shell.CreateShortcut($matching)
    if ($fixed.IconLocation -notlike '*twitter-large.ico*') { throw 'Failed: PWA icon location not updated.' }
    foreach ($unchanged in @($unrelated,$wrongBrowser)) {
        if ($shell.CreateShortcut($unchanged).IconLocation -notlike '*shell32.dll*') { throw 'Failed: unrelated shortcut modified.' }
    }
    Write-Host 'PASS: Windows PWA shortcut targeted; unrelated links preserved' -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $tempFolder -Force -Recurse -ErrorAction SilentlyContinue
}
