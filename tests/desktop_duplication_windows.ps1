# Integration test: Windows PowerShell 5.1, isolated temp files + one disposable HKCU key.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'scripts\Twitter.Common.ps1')
$temp = Join-Path $env:TEMP ('twitter-dup-test-' + [guid]::NewGuid().ToString('N'))
$key = 'HKCU:\Software\TwitterBlueBirdRestorerTest\' + [guid]::NewGuid().ToString('N')
New-Item -Path $temp -ItemType Directory -Force | Out-Null
try {
    $script:SelectedBrowser = Get-BrowserDefinition 'brave'
    $script:DataRoot = Join-Path $temp 'Data'
    $script:PolicyKey = $key
    $script:PolicyStatePath = Join-Path $script:DataRoot 'Policy\installed-policy.json'
    New-Item -Path (Split-Path -Parent $script:PolicyStatePath) -ItemType Directory -Force | Out-Null
    New-Item -Path 'HKCU:\Software\TwitterBlueBirdRestorerTest' -Force | Out-Null
    New-Item -Path $key -Force | Out-Null
    $originalPolicy = '[{"url":"https://x.com/","default_launch_container":"window","create_desktop_shortcut":true,"custom_name":"Twitter","custom_icon":{"url":"https://example.org/bird.png","hash":"abc"}}]'
    New-ItemProperty -Path $key -Name $script:PolicyName -PropertyType String -Value $originalPolicy -Force | Out-Null
    [pscustomobject]@{policyValue=$originalPolicy;createdAt='test'} | ConvertTo-Json | Set-Content -LiteralPath $script:PolicyStatePath -Encoding UTF8
    if (-not (Disable-OwnedTwitterPolicyDesktopShortcut)) { throw 'Expected migration to change the policy.' }
    $migrated = Get-PolicyValue
    $parsedMigrated = ConvertFrom-Json -InputObject $migrated -ErrorAction Stop
    $entry = $parsedMigrated[0]
    if ($entry.create_desktop_shortcut -ne $false -or $entry.custom_name -ne 'Twitter' -or $entry.custom_icon.hash -ne 'abc') {
        throw 'Migration modified other policy attributes.'
    }
    $owner = Get-Content -LiteralPath $script:PolicyStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($owner.policyValue -cne $migrated) { throw 'Owned policy record was not updated.' }
    # File.Replace must succeed with three concrete absolute paths and clean
    # its temporary ownership backup after successful migration.
    $stateDir = Split-Path -Parent $script:PolicyStatePath
    $residual = @(Get-ChildItem -LiteralPath $stateDir -File -Filter 'installed-policy.json.*' -ErrorAction SilentlyContinue)
    if ($residual.Count -ne 0) { throw 'Temporary migration or backup files were left behind.' }
    if (-not (Test-Path -LiteralPath $script:PolicyStatePath -PathType Leaf)) { throw 'Migration removed the owned policy record.' }
    if (Disable-OwnedTwitterPolicyDesktopShortcut) { throw 'Second migration should be a no-op.' }
    # A root array with one entry is valid. A root object, empty array, multiple
    # entries, or a policy for another site must never pass validation.
    foreach ($invalidPolicy in @(
        '{"url":"https://x.com/","custom_name":"Twitter"}',
        '[]',
        '[{"url":"https://x.com/","custom_name":"Twitter"},{"url":"https://x.com/","custom_name":"Twitter"}]',
        '[{"url":"https://example.com/","custom_name":"Twitter"}]',
        '[{"url":"https://x.com/","custom_name":"Other"}]'
    )) {
        $blocked = $false
        try { $null = ConvertTo-TwitterSingleShortcutPolicy -PolicyJson $invalidPolicy } catch { $blocked = $true }
        if (-not $blocked) { throw ('Unexpected policy accepted: ' + $invalidPolicy) }
    }
    # Valid conversion must keep all other attributes unchanged.
    $unchanged = ConvertTo-TwitterSingleShortcutPolicy -PolicyJson $migrated
    $parsedUnchanged = ConvertFrom-Json -InputObject $unchanged -ErrorAction Stop
    if (-not ($parsedUnchanged -is [array]) -or $parsedUnchanged.Count -ne 1 -or
        $parsedUnchanged[0].custom_icon.hash -ne 'abc' -or
        $parsedUnchanged[0].create_desktop_shortcut -ne $false) {
        throw 'Converting an already migrated policy must preserve its data.'
    }
    # Reject a third-party policy, without changing it or rewriting the owner record.
    Set-ItemProperty -LiteralPath $key -Name $script:PolicyName -Value $originalPolicy
    $rejected = $false
    try { $null = Disable-OwnedTwitterPolicyDesktopShortcut } catch { $rejected = $true }
    if (-not $rejected -or (Get-PolicyValue) -cne $originalPolicy) { throw 'Foreign policy was not protected.' }
    # Shortcut fixture: same app + another app + misleading non-Twitter URL.
    $desktop = Join-Path $temp 'Desktop'
    New-Item -Path $desktop -ItemType Directory -Force | Out-Null
    $exe = Join-Path $temp 'BraveSoftware\Brave-Browser\Application\brave_proxy.exe'
    New-Item -Path (Split-Path -Parent $exe) -ItemType Directory -Force | Out-Null
    [IO.File]::WriteAllBytes($exe,[byte[]]@(77,90,0,0))
    $shell = New-Object -ComObject WScript.Shell
    function New-TwitterLink([string]$Name,[string]$Arguments) {
        $path = Join-Path $desktop ($Name + '.lnk')
        $link = $shell.CreateShortcut($path)
        $link.TargetPath = $exe
        $link.Arguments = $Arguments
        $link.IconLocation = 'C:\Windows\System32\shell32.dll,0'
        $link.Save()
        return $path
    }
    $args = '--profile-directory=Default --app-id=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    $canonical = New-TwitterLink 'Twitter' $args
    $duplicate = New-TwitterLink 'Twitter (2)' $args
    $unrelated = New-TwitterLink 'Twitter (3)' '--profile-directory=Default --app-id=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    $malicious = New-TwitterLink 'Twitter (4)' '--app=https://x.com.evil.example/'
    $before = @(Get-TwitterDuplicateDesktopShortcuts -Desktop $desktop)
    if ($before.Count -ne 1 -or $before[0].Name -cne 'Twitter (2).lnk') { throw 'Duplicates selector chose unrelated links.' }
    $moved = Backup-TwitterDuplicateDesktopShortcuts -Desktop $desktop
    if ($moved -ne 1) { throw 'Expected one duplicate to be backed up.' }
    foreach ($retained in @($canonical,$unrelated,$malicious)) {
        if (-not (Test-Path -LiteralPath $retained)) { throw ('Shortcut was incorrectly removed: ' + $retained) }
    }
    if (Test-Path -LiteralPath $duplicate) { throw 'Numbered duplicate was left on desktop.' }
    if ((Backup-TwitterDuplicateDesktopShortcuts -Desktop $desktop) -ne 0) { throw 'Second cleanup must be a no-op.' }
    $backups = @(Get-ChildItem -LiteralPath (Join-Path $script:DataRoot 'DesktopShortcutBackups') -Filter 'Twitter (2).lnk' -File -Recurse)
    if ($backups.Count -ne 1) { throw 'Moved duplicate was not backed up.' }
    Write-Host 'PASS: browser auto-shortcut policy migrated; duplicates backed up safely and idempotently' -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $key -Force -Recurse -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temp -Force -Recurse -ErrorAction SilentlyContinue
}
