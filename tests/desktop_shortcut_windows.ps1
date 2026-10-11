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
    # The hosted Windows runner does not have Brave installed. An unresolved
    # shortcut target can be normalized away by WScript.Shell. Use real files
    # inside the disposable fixture, with browser-shaped paths for matching.
    $exe = Join-Path $tempFolder 'BraveSoftware\Brave-Browser\Application\brave_proxy.exe'
    $edgeExe = Join-Path $tempFolder 'Microsoft\Edge\Application\msedge_proxy.exe'
    foreach ($binary in @($exe,$edgeExe)) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $binary) -Force | Out-Null
        [IO.File]::WriteAllBytes($binary, [byte[]]@(77,90,0,0))
    }
    $matching = New-SyntheticShortcut -Name 'Twitter' -Arguments '--profile-directory=Default --app-id=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' -Executable $exe
    $unrelated = New-SyntheticShortcut -Name 'Twitter (normal browser)' -Arguments 'https://x.com/' -Executable $exe
    $wrongBrowser = New-SyntheticShortcut -Name 'Twitter (Edge)' -Arguments '--app-id=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' -Executable $edgeExe
    $fakeApp = New-SyntheticShortcut -Name 'Twitter (unrelated PWA)' -Arguments '--app-id=cccccccccccccccccccccccccccccccc' -Executable $exe
    $wrongUrl = New-SyntheticShortcut -Name 'Twitter (2)' -Arguments '--app=https://x.com.evil.example/' -Executable $exe
    $urlApp = New-SyntheticShortcut -Name 'Twitter (Brave)' -Arguments '--app=https://x.com/home' -Executable $exe
    $expected = @($matching, $urlApp)
    $found = @(Get-TwitterDesktopLinks -Folders @($tempFolder))
    $foundNames = @($found | ForEach-Object { $_.FullName })
    if ($found.Count -ne $expected.Count -or @(Compare-Object $expected $foundNames).Count -gt 0) {
        # Diagnostics distinguish a missing match from an accidental extra match.
        foreach ($item in @(Get-ChildItem -LiteralPath $tempFolder -Filter '*.lnk' -File)) {
            $readBack = $shell.CreateShortcut($item.FullName)
            Write-Host ('CHECK: ' + $item.Name + ' target=' + $readBack.TargetPath + ' args=' + $readBack.Arguments)
        }
        throw ('Failed: expected ' + ($expected -join ', ') + '; found ' + ($foundNames -join ', '))
    }
    $changed = Repair-TwitterDesktopIcons -Folders @($tempFolder)
    if ($changed -ne $expected.Count) { throw ('Failed: expected ' + $expected.Count + ' repaired PWA links, got ' + $changed) }
    foreach ($name in $expected) {
        $fixed = $shell.CreateShortcut($name)
        if ($fixed.IconLocation -notlike '*twitter-large.ico*') { throw ('Failed: PWA icon location not updated: ' + $name) }
    }
    foreach ($unchanged in @($unrelated,$wrongBrowser,$fakeApp,$wrongUrl)) {
        if ($shell.CreateShortcut($unchanged).IconLocation -notlike '*shell32.dll*') { throw 'Failed: unrelated shortcut modified.' }
    }
    Write-Host 'PASS: Windows PWA shortcut targeted; unrelated links preserved' -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $tempFolder -Force -Recurse -ErrorAction SilentlyContinue
}
