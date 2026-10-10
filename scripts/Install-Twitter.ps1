# Installs/repairs the Twitter PWA policy and stages latest extension in a stable folder.
[CmdletBinding()]
param([switch]$SkipBrowserRestart, [switch]$SkipScheduledUpdates, [switch]$FreshPwa)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Twitter.Common.ps1')

try {
    $brave = Find-Brave
    $config = Get-KitConfig
    Write-Host 'Twitter Blue Bird Restorer - Setup' -ForegroundColor Cyan
    Write-Host ('Brave: ' + $brave)
    if ($config.github_repo) { Write-Host ('Latest releases: https://github.com/' + $config.github_repo + '/releases/latest') }
    else { Write-Warning 'GitHub repo is not configured yet; bundled extension is used, and automatic updates are disabled.' }

    Sync-TwitterExtension
    # A full reinstall requires Brave to observe the policy's removal before reapplying it.
    if ($FreshPwa -and -not $SkipBrowserRestart) {
        $removed = Remove-OwnedPolicyForFreshInstall
        if ($removed) {
            Write-Host 'Restarting Brave with the old policy removed to refresh PWA registration.'
            Restart-BraveGracefully -brave $brave -page 'brave://apps'
            Start-Sleep -Seconds 12
            Close-BraveGracefully
        }
    }
    Set-TwitterPolicy

    # Install the updater's own source scripts so the scheduled task does not rely on Downloads/Desktop.
    $updaterDir = Join-Path $script:DataRoot 'Updater'
    New-Item -ItemType Directory -Path $updaterDir -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Twitter.Common.ps1') -Destination (Join-Path $updaterDir 'Twitter.Common.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Update-Twitter.ps1') -Destination (Join-Path $updaterDir 'Update-Twitter.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $script:KitRoot 'config.json') -Destination (Join-Path $script:DataRoot 'config.json') -Force
    # The Common module expects config.json one directory above scripts and bundled icons there.
    # DataRoot/Updater and DataRoot/config.json satisfy the layout during scheduled updates.
    if (-not $SkipScheduledUpdates -and $config.github_repo) {
        try {
            $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $updaterDir 'Update-Twitter.ps1') + '" -Silent')
            $trigger = New-ScheduledTaskTrigger -Daily -At '09:00'
            Register-ScheduledTask -TaskName 'TwitterBlueBirdRestorerUpdate' -Action $action -Trigger $trigger -Description 'Check latest Twitter extension GitHub release daily' -Force | Out-Null
            Write-Host 'Automatic update check scheduled daily at 09:00.' -ForegroundColor Green
        } catch { Write-Warning ('Could not register update task: ' + $_.Exception.Message) }
    }

    if (-not $SkipBrowserRestart) {
        Write-Host 'Restarting Brave to apply the new Twitter policy.'
        Restart-BraveGracefully -brave $brave -page 'brave://apps'
        Write-Host 'Waiting for Brave to create the new Twitter PWA shortcut...'
    }

    $desktopOk = $false
    if (-not $SkipBrowserRestart) {
        for ($i = 0; $i -lt 35; $i++) {
            if (Ensure-TwitterDesktopShortcut) { $desktopOk = $true; break }
            Start-Sleep -Seconds 2
        }
    } else { $desktopOk = Ensure-TwitterDesktopShortcut }
    if (-not $desktopOk) {
        Write-Warning 'Twitter desktop shortcut is not ready. Wait for Brave PWA installation, then run this setup again.'
    } else {
        try { Invoke-Item -LiteralPath (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Twitter.lnk') }
        catch { Write-Warning ('Could not launch Twitter app shortcut: ' + $_.Exception.Message) }
    }

    try {
        & (Join-Path $PSScriptRoot 'Fix-Twitter-Taskbar.ps1') -Style White-Circle
    } catch { Write-Host 'Taskbar icon update will be available after pinning Twitter.' }

    # The browser controls initial unpacked-extension approval and Windows controls taskbar pin consent.
    Write-Host ''
    Write-Host 'Two one-time UI actions may be needed:' -ForegroundColor Yellow
    Write-Host ('  1. brave://extensions -> Developer mode -> Load unpacked: ' + $script:ExtensionRoot)
    Write-Host '  2. brave://apps -> Launch Twitter -> right-click taskbar icon -> Pin to taskbar.'
    Write-Host 'Your Twitter PWA name/icon is managed by WebAppInstallForceList.' -ForegroundColor Green
    Write-Host ('Extension files stay at: ' + $script:ExtensionRoot)
    if ($config.github_repo) { Write-Host 'Future runs fetch latest release, and the daily updater checks for new files.' }
} catch {
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
