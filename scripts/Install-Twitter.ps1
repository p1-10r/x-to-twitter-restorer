# Installs/repairs the Twitter PWA policy and stages latest extension in a stable folder.
[CmdletBinding()]
param([ValidateSet('Auto','Brave','Chrome','Edge')][string]$Browser = 'Auto', [switch]$SkipBrowserRestart, [switch]$SkipScheduledUpdates, [switch]$FreshPwa, [switch]$ElevationChild, [string]$OriginalSid = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Twitter.Common.ps1')
. (Join-Path $PSScriptRoot 'Twitter.Elevation.ps1')

$script:PolicyTemporarilyRemoved = $false
try {
    if (-not $OriginalSid) { $OriginalSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }
    $forward = @('-Browser', $Browser)
    if ($SkipBrowserRestart) { $forward += '-SkipBrowserRestart' }
    if ($SkipScheduledUpdates) { $forward += '-SkipScheduledUpdates' }
    if ($FreshPwa) { $forward += '-FreshPwa' }
    $forward += '-ElevationChild'
    $elevatedChildRan = Invoke-TwitterElevation -ScriptPath $PSCommandPath -OriginalSid $OriginalSid -RelaunchArguments $forward
    if ($elevatedChildRan) { return }
    $selected = Select-TwitterBrowser -Requested $Browser
    Initialize-TwitterBrowser $selected
    $browserExe = Find-BrowserExecutable $selected
    $appsUrl = $selected.Scheme + "://apps"
    $extensionsUrl = $selected.Scheme + "://extensions"
    $config = Get-KitConfig
    $kitManifest = Join-Path $script:KitRoot 'extension\manifest.json'
    $kitVersion = [string](Get-Content -LiteralPath $kitManifest -Raw -Encoding UTF8 | ConvertFrom-Json).version
    Write-Host ('Installer source: ' + $script:KitRoot + ' (v' + $kitVersion + ')') -ForegroundColor Cyan
    $existingApps = @(Get-BrowserTwitterAppRegistrations)
    # Prefer the profile of the already-installed X/Twitter app.
    $extensionProfile = if ($existingApps.Count -eq 1) { [string]$existingApps[0].Profile } else { Get-TwitterTargetProfile }
    if ($existingApps.Count -gt 1 -and @($existingApps | Select-Object -ExpandProperty Profile -Unique).Count -gt 1) {
        throw 'X/Twitter apps are installed in multiple profiles. Run the setup separately per browser profile or remove extra apps manually.'
    }
    $existingPolicy = Get-PolicyValue
    $hasOwnedPolicy = Test-Path -LiteralPath $script:PolicyStatePath
    if ($existingPolicy -and -not $hasOwnedPolicy) {
        throw 'Another WebAppInstallForceList policy is present; no settings were changed.'
    }
    Write-Host 'Twitter Blue Bird Restorer - Setup' -ForegroundColor Cyan
    Write-Host ('Target browser: ' + $selected.DisplayName + ' (' + $browserExe + ')')
    if ($config.github_repo) { Write-Host ('Updates: https://github.com/' + $config.github_repo + '/releases/latest') }
    Write-Host ''
    Write-Host '【変更内容と承認のお願い】' -ForegroundColor Yellow
    Write-Host '・拡張機能はx.comの見た目（ロゴ、favicon、メニュー名、タイトル、PWA設定）を書き換えます。'
    Write-Host '・投稿本文、ユーザー作成文章、プロフィール、入力中の文字は変更しません。'
    Write-Host ('・Windowsレジストリ ' + ($script:PolicyKey -replace '^HKCU:', 'HKCU') + ' のWebAppInstallForceListを変更します。')
    Write-Host '・デスクトップとPWAショートカット、毎日9時の更新タスクを変更します。'
    Write-Host '・選択したブラウザを終了・再起動します。未保存の下書きや開いている作業を先に保存してください。'
    Write-Host '・スクリプトはサイトデータ、Cookie、ログイン情報、閲覧履歴を削除しません。'
    Write-Host '・ブラウザのアンインストール確認が出たら【閲覧データも削除】のチェックを入れないでください。'
    Write-Host '・同じWindowsユーザーの他のブラウザプロファイルにも影響する場合があります。'
    if ($existingApps.Count -gt 0) {
        Write-Host '【アンインストール後に再インストールする既存アプリ】' -ForegroundColor Yellow
        foreach ($app in $existingApps) { Write-Host ('  ' + $app.DisplayName + ' [profile: ' + $app.Profile + ']') }
    } elseif ($FreshPwa -and $existingPolicy) {
        Write-Host '【既存PWAを更新するため、旧ポリシーを一時的に解除します】' -ForegroundColor Yellow
    } else {
        Write-Host '登録済みの選択したブラウザのTwitter/Xアプリは検出されませんでした。'
    }
    if ((Read-Host '上記内容に同意して実行する場合は REINSTALL と入力（それ以外は中止）') -cne 'REINSTALL') {
        Write-Host '中止しました。設定は変更していません。'
        return
    }
    # Stage the latest extension and verify browser registration BEFORE uninstalling any app
    # or changing WebAppInstallForceList. Browser approval is always user-driven.
    Sync-TwitterExtension
    if ($existingApps.Count -eq 0) {
        $currentStatus = Get-TwitterExtensionStatus -Profile $extensionProfile
        if (-not $currentStatus.Installed) {
            $foundProfiles = @(Get-TwitterEnabledProfiles)
            if ($foundProfiles.Count -eq 1) {
                $extensionProfile = [string]$foundProfiles[0].Profile
                Write-Host ('Extension detected automatically in profile ' + $extensionProfile + '; using that profile for PWA installation.') -ForegroundColor Cyan
            } elseif ($foundProfiles.Count -gt 1) {
                Write-Warning 'Extension enabled in multiple profiles. Select the browser profile for PWA installation.'
                foreach ($found in $foundProfiles) { Write-Host ('  ' + $found.Profile + ' : ' + $found.Id) }
                $chosenProfile = (Read-Host 'Enter exact profile directory (Enter cancels)').Trim()
                if (@($foundProfiles | Where-Object { $_.Profile -ceq $chosenProfile }).Count -ne 1) {
                    throw 'Browser profile selection cancelled or invalid; no PWA was removed.'
                }
                $extensionProfile = $chosenProfile
            }
        }
    }
    Assert-TwitterExtensionReady -Executable $browserExe -ExtensionsUrl $extensionsUrl -Profile $extensionProfile
    Assert-TwitterPublishedIconReady
    # Close the browser BEFORE removing any owned policy. An aborted close
    # therefore does not change registry state or orphan the previous PWA.
    if (-not $SkipBrowserRestart) { Close-BrowserGracefully }
    # The owned policy must first be removed and observed by the selected browser before a force-installed app can be uninstalled.
    if (-not $SkipBrowserRestart -and ($FreshPwa -or $existingApps.Count -gt 0)) {
        $script:PolicyTemporarilyRemoved = Remove-OwnedPolicyForFreshInstall
        if ($script:PolicyTemporarilyRemoved) {
            Restart-BrowserGracefully -Executable $browserExe -Page $appsUrl -Profile $extensionProfile
            Write-Host 'Waiting for the browser to recognize removal of the forced-install policy...'
            Start-Sleep -Seconds 10
        }
        # After policy removal the browser may have already uninstalled policy-controlled PWAs.
        $pending = @(Get-BrowserTwitterAppRegistrations)
        if ($pending.Count -gt 0) { Assert-BrowserPwaUninstalled -Expected $pending -Executable $browserExe }
        if (@(Get-BrowserTwitterAppRegistrations).Count -gt 0) {
            throw 'An existing X/Twitter app is still installed. Nothing will be reinstalled until it is removed.'
        }
        Close-BrowserGracefully
    } elseif ($existingApps.Count -gt 0) {
        throw 'Existing apps require a browser restart and native uninstall; remove SkipBrowserRestart and retry.'
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
        Write-Host ('Restarting ' + $selected.DisplayName + ' to apply the new Twitter policy.')
        Restart-BrowserGracefully -Executable $browserExe -Page $appsUrl -Profile $extensionProfile
        Write-Host 'Waiting for the browser to create the new Twitter PWA shortcut...'
    }

    $desktopShortcut = $null
    if (-not $SkipBrowserRestart) {
        for ($i = 0; $i -lt 35; $i++) {
            $desktopShortcut = Ensure-TwitterDesktopShortcut
            if ($desktopShortcut) { break }
            Start-Sleep -Seconds 2
        }
    } else { $desktopShortcut = Ensure-TwitterDesktopShortcut }
    if (-not $desktopShortcut) {
        Write-Warning 'Twitter desktop shortcut is not ready. Wait for PWA installation, then run this setup again.'
    } else {
        try { Invoke-Item -LiteralPath $desktopShortcut }
        catch { Write-Warning ('Could not launch Twitter app shortcut: ' + $_.Exception.Message) }
    }

    # Remove only numerically suffixed duplicates of our own PWA launcher.
    # Every moved link is retained in AppData for recovery.
    $null = Backup-TwitterDuplicateDesktopShortcuts

    # Chromium can create a second default desktop shortcut after our first
    # link was updated. Repair all matching PWA links once more after launch.
    if ($desktopShortcut -and -not $SkipBrowserRestart) {
        Start-Sleep -Seconds 3
        $null = Repair-TwitterDesktopIcons
    }
    try {
        & (Join-Path $PSScriptRoot 'Fix-Twitter-Taskbar.ps1') -Style Big-Blue-Bird -Browser $selected.Id
    } catch { Write-Host 'Taskbar icon update will be available after pinning Twitter.' }

    # The browser controls initial unpacked-extension approval and Windows controls taskbar pin consent.
    Write-Host ''
    Write-Host 'Extension and taskbar status:' -ForegroundColor Yellow
    Write-Host '  1. The extension was verified during this setup (no action needed).'
    Write-Host ('  2. ' + $appsUrl + ' -> Launch Twitter -> right-click taskbar icon -> Pin to taskbar (if not pinned).')
    Write-Host 'The selected browser manages the Twitter PWA name/icon through WebAppInstallForceList.' -ForegroundColor Green
    Write-Host ('Extension files stay at: ' + $script:ExtensionRoot)
    if ($config.github_repo) { Write-Host 'Future runs fetch latest release, and the daily updater checks for new files.' }
} catch {
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    if ($script:PolicyTemporarilyRemoved) {
        try { Restore-OwnedPolicyAfterAbort }
        catch { Write-Warning ('Policy restore failed: ' + $_.Exception.Message) }
    }
    if ($ElevationChild -and [Environment]::UserInteractive) {
        try { $null = Read-Host 'Elevated setup failed. Press Enter after reading the error' } catch { }
    }
    throw 'Twitter setup failed. See ERROR above.'
}
