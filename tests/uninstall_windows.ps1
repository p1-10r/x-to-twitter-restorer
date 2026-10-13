# Windows PowerShell 5.1: only a disposable per-user registry key and temp files.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'scripts\Twitter.Common.ps1')
. (Join-Path $root 'scripts\Twitter.Uninstall.ps1')
$temp = Join-Path $env:TEMP ('twitter-uninstall-test-' + [guid]::NewGuid().ToString('N'))
$key = 'HKCU:\Software\TwitterBlueBirdRestorerUninstallTest\' + [guid]::NewGuid().ToString('N')
New-Item -ItemType Directory -Path $temp -Force | Out-Null
try {
    $script:DataRoot = Join-Path $temp 'TwitterBlueBirdRestorer'
    $script:PolicyName = 'WebAppInstallForceList'
    $browser = Get-BrowserDefinition 'brave'
    $browser.PolicyKey = $key
    $policyFile = Join-Path $script:DataRoot 'Policy\installed-policy.json'
    New-Item -Path (Split-Path -Parent $policyFile) -ItemType Directory -Force | Out-Null
    New-Item -Path 'HKCU:\Software\TwitterBlueBirdRestorerUninstallTest' -Force | Out-Null
    New-Item -Path $key -Force | Out-Null
    $value = '[{"url":"https://x.com/","create_desktop_shortcut":false,"custom_name":"Twitter"}]'
    New-ItemProperty -LiteralPath $key -Name 'WebAppInstallForceList' -PropertyType String -Value $value -Force | Out-Null
    [pscustomobject]@{ policyValue = $value } | ConvertTo-Json | Set-Content -LiteralPath $policyFile -Encoding UTF8
    $record = Get-TwitterOwnedPolicyRecord -Browser $browser
    if (-not $record.Owned -or -not $record.Current) { throw 'Owned policy was not detected.' }
    # Never remove a policy changed since our kit wrote its ownership record.
    $foreign = '[{"url":"https://other.example/"}]'
    Set-ItemProperty -LiteralPath $key -Name 'WebAppInstallForceList' -Value $foreign
    $blocked = $false
    try { $null = Remove-TwitterOwnedPolicyValue -Record $record } catch { $blocked = $true }
    if (-not $blocked -or (Get-PolicyValue) -cne $foreign) { throw 'Externally modified policy was not protected.' }
    Set-ItemProperty -LiteralPath $key -Name 'WebAppInstallForceList' -Value $value
    if (-not (Remove-TwitterOwnedPolicyValue -Record $record)) { throw 'Owned policy removal did not report change.' }
    if ((Get-PolicyValue)) { throw 'Owned policy value still exists.' }
    if (Remove-TwitterOwnedPolicyValue -Record $record) { throw 'Second removal should be a no-op.' }
    if (-not (Test-Path -LiteralPath $policyFile)) { throw 'Ownership record must remain until browser UI removal completes.' }
    # Verify the task action is exactly our updater, not a name collision.
    $action = [pscustomobject]@{Execute='powershell.exe';Arguments=('-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $script:DataRoot 'Updater\Update-Twitter.ps1') + '" -Silent')}
    $task = [pscustomobject]@{Actions=@($action)}
    if (-not (Test-TwitterUpdaterTaskOwned -Task $task -DataRoot $script:DataRoot)) { throw 'Owned updater task was not recognized.' }
    $action.Arguments = '-NoProfile -File "C:\Temp\Unrelated.ps1"'
    if (Test-TwitterUpdaterTaskOwned -Task $task -DataRoot $script:DataRoot) { throw 'Unrelated updater task would be removed.' }
    # A foreign policy lacking an ownership record is never changed.
    Remove-Item -LiteralPath $policyFile -Force
    Set-ItemProperty -LiteralPath $key -Name 'WebAppInstallForceList' -Value $foreign
    $unowned = Get-TwitterOwnedPolicyRecord -Browser $browser
    if ($unowned.Owned -or (Remove-TwitterOwnedPolicyValue -Record $unowned)) { throw 'Foreign policy was changed.' }
    if ((Get-PolicyValue) -cne $foreign) { throw 'Foreign registry value changed.' }
    Write-Host 'PASS: uninstall ownership protection, task validation and repeat-safe removal.' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse -Force }
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
