# Removes only Twitter Blue Bird Restorer's own Windows modifications.
# Browser-native UI must remove the unpacked extension and PWA; never mutate
# Chromium's Preferences/Secure Preferences or delete website data.
[CmdletBinding()]
param([switch]$ElevationChild,[string]$OriginalSid = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Twitter.Common.ps1')
. (Join-Path $PSScriptRoot 'Twitter.Uninstall.ps1')
. (Join-Path $PSScriptRoot 'Twitter.Elevation.ps1')
try {
    if (-not $OriginalSid) { $OriginalSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }
    if (Invoke-TwitterElevation -ScriptPath $PSCommandPath -OriginalSid $OriginalSid -RelaunchArguments @('-ElevationChild')) { return }
    $browsers = @(@('brave','chrome','edge') | ForEach-Object { Get-BrowserDefinition $_ })
    $policyPlans = New-Object 'System.Collections.Generic.List[object]'
    $affected = New-Object 'System.Collections.Generic.List[object]'
    $extensionCount = 0
    $pwaCount = 0
    Write-Host 'Twitter Blue Bird Restorer - COMPLETE UNINSTALL' -ForegroundColor Cyan
    Write-Host 'Scanning current Windows account (Brave / Chrome / Edge)...'
    foreach ($browser in $browsers) {
        $plan = Get-TwitterOwnedPolicyRecord -Browser $browser
        $policyPlans.Add($plan)
        if ($plan.Current -and -not $plan.Owned) {
            Write-Warning ($browser.DisplayName + ': unmanaged WebAppInstallForceList exists; it will NOT be changed.')
        }
        Initialize-TwitterBrowser $browser
        $profiles = @(Get-TwitterBrowserExtensionRegistrations -Browser $browser)
        $apps = @(Get-BrowserTwitterAppRegistrations)
        $extensionCount += $profiles.Count
        if ($plan.Owned) { $pwaCount += $apps.Count }
        if ($plan.Owned -or $profiles.Count -gt 0) {
            $affected.Add($browser)
            Write-Host ('Browser: ' + $browser.DisplayName + ' | owned policy: ' + $plan.Owned + ' | extension profiles: ' + $profiles.Count + ' | X/Twitter apps: ' + $apps.Count)
            foreach ($status in $profiles) { Write-Host ('  Extension profile: ' + $status.Profile + ' | ID: ' + $status.Id) }
            if ($plan.Owned) { foreach ($app in $apps) { Write-Host ('  PWA: ' + $app.DisplayName + ' | profile: ' + $app.Profile) } }
        }
    }
    $task = Get-ScheduledTask -TaskName 'TwitterBlueBirdRestorerUpdate' -ErrorAction SilentlyContinue
    if ($task -and -not (Test-TwitterUpdaterTaskOwned -Task $task -DataRoot $script:DataRoot)) {
        throw 'A scheduled task with the same name is not owned by this kit. Refusing to modify it.'
    }
    $hasArtifacts = Test-Path -LiteralPath $script:DataRoot
    Write-Host ''
    Write-Host 'This procedure WILL:' -ForegroundColor Yellow
    Write-Host '  - Unregister only kit-owned PWA force-install policies in all three browsers'
    Write-Host '  - Unregister the owned daily update task'
    Write-Host '  - Require you to REMOVE the unpacked extension in each browser profile (not just disable it)'
    Write-Host '  - Open affected browsers so you can remove the extension and Twitter PWA in the UI'
    Write-Host '  - After verifying removal and browser exit, delete the unpacked extension folder'
    Write-Host '  - Remove identified kit-owned shortcuts, blue icons and restorer data files'
    Write-Host 'This procedure will NOT delete browser profiles, cookies, site data, passwords, history, or posts.'
    Write-Host 'NOTE: If the extension remains in Brave/Chrome/Edge, you MUST manually remove it.' -ForegroundColor Yellow
    Write-Host 'If you originally installed the X PWA, uninstalling Twitter does not recreate that original app.' -ForegroundColor Yellow
    if (-not $hasArtifacts -and -not $task -and $affected.Count -eq 0) {
        Write-Host 'No managed installation was found. If the extension is still visible, remove it manually:' -ForegroundColor Yellow
        Show-TwitterExtensionManualRemovalInstructions -Browsers $browsers
        Write-Host 'No kit-managed settings were modified.'
        return
    }
    if ((Read-Host 'Type UNINSTALL to proceed (anything else cancels)') -cne 'UNINSTALL') {
        Write-Host 'Cancelled before any change.'
        return
    }
    foreach ($plan in $policyPlans) { $null = Remove-TwitterOwnedPolicyValue -Record $plan }
    if ($task) {
        # Recheck ownership against the current task action before deleting.
        $freshTask = Get-ScheduledTask -TaskName 'TwitterBlueBirdRestorerUpdate' -ErrorAction SilentlyContinue
        if ($freshTask) {
            if (-not (Test-TwitterUpdaterTaskOwned -Task $freshTask -DataRoot $script:DataRoot)) { throw 'Update task changed; not removed.' }
            Unregister-ScheduledTask -TaskName 'TwitterBlueBirdRestorerUpdate' -Confirm:$false -ErrorAction Stop
            Write-Host 'Removed daily update task.' -ForegroundColor Green
        }
    }
    Write-Host ''
    if ($affected.Count -gt 0) {
        Write-Host 'MANUAL BROWSER APPROVAL REQUIRED' -ForegroundColor Yellow
        Show-TwitterExtensionManualRemovalInstructions -Browsers $browsers
        Write-Host 'In browser Apps, REMOVE the Twitter app installed by the kit. Keep Delete browsing data UNCHECKED.'
        # The browser must reread the removed force-install policy before its
        # app manager will allow uninstall. Ask before closing unsaved tabs.
        foreach ($browser in $affected) {
            Initialize-TwitterBrowser $browser
            if (@(Get-TargetBrowserProcesses).Count -gt 0) {
                Write-Host ('Restart required for policy removal: ' + $browser.DisplayName) -ForegroundColor Yellow
                Close-BrowserGracefully
            }
        }
        foreach ($browser in $affected) {
            $exe = Find-BrowserExecutable $browser
            if (-not $exe) { Write-Warning ($browser.DisplayName + ' not installed; clear its extension registration using the browser before uninstall can finish.'); continue }
            Initialize-TwitterBrowser $browser
            $profiles = @(Get-TwitterBrowserExtensionRegistrations -Browser $browser)
            $seen = New-Object 'System.Collections.Generic.List[string]'
            foreach ($record in $profiles) { if (-not $seen.Contains($record.Profile)) { $seen.Add($record.Profile) } }
            if ($seen.Count -eq 0) { $seen.Add('Default') }
            foreach ($profile in $seen) {
                Write-Host ('Opening ' + $browser.DisplayName + ' profile ' + $profile + ' extension manager...') -ForegroundColor Cyan
                Start-Process -FilePath $exe -ArgumentList @(('--profile-directory="' + $profile + '"'),($browser.Scheme + '://extensions')) | Out-Null
            }
            if (@($policyPlans | Where-Object { $_.Browser.Id -eq $browser.Id -and $_.Owned }).Count -gt 0) {
                $apps = @(Get-BrowserTwitterAppRegistrations)
                $appProfiles = @($apps | Select-Object -ExpandProperty Profile -Unique)
                if ($appProfiles.Count -eq 0) { $appProfiles = @('Default') }
                foreach ($profile in $appProfiles) {
                    Write-Host ('Opening ' + $browser.DisplayName + ' profile ' + $profile + ' app manager...') -ForegroundColor Cyan
                    Start-Process -FilePath $exe -ArgumentList @(('--profile-directory="' + $profile + '"'),($browser.Scheme + '://apps')) | Out-Null
                }
            }
        }
        if ((Read-Host 'After checking EVERY browser profile and removing the extension/PWA in the UI, type REMOVED (anything else stops safely)') -cne 'REMOVED') {
            Write-Warning 'Partially finished. Policies and update task were cleared; no extension files or shortcuts were deleted. Run this tool again after browser removal.'
            exit 2
        }
        foreach ($browser in $affected) {
            Initialize-TwitterBrowser $browser
            if (@(Get-TargetBrowserProcesses).Count -gt 0) {
                Write-Host ('Please exit ' + $browser.DisplayName + ' to let it save its extension settings.') -ForegroundColor Yellow
                Close-BrowserGracefully
            }
        }
        $stillRegistered = New-Object 'System.Collections.Generic.List[string]'
        foreach ($browser in $affected) {
            Initialize-TwitterBrowser $browser
            foreach ($record in @(Get-TwitterBrowserExtensionRegistrations -Browser $browser)) {
                $stillRegistered.Add(($browser.DisplayName + '/' + $record.Profile + ' ID=' + $record.Id))
            }
            $owned = @($policyPlans | Where-Object { $_.Browser.Id -eq $browser.Id -and $_.Owned })
            if ($owned.Count -gt 0) {
                foreach ($app in @(Get-BrowserTwitterAppRegistrations)) {
                    $stillRegistered.Add(($browser.DisplayName + '/PWA ' + $app.DisplayName + ' profile=' + $app.Profile))
                }
            }
        }
        if ($stillRegistered.Count -gt 0) {
            foreach ($entry in $stillRegistered) { Write-Warning ('Still registered: ' + $entry) }
            Show-TwitterExtensionManualRemovalInstructions -Browsers $browsers
            throw 'Browser removal was not confirmed on disk. Files were retained. Click Remove in the extensions UI, exit browsers, and rerun this tool.'
        }
    } elseif ($hasArtifacts) {
        # Some browser versions do not expose unpacked extension registration in
        # saved preferences. Require manual inspection even if detection found 0.
        Write-Host 'No owned extension registration was detected, but kit files remain.' -ForegroundColor Yellow
        Show-TwitterExtensionManualRemovalInstructions -Browsers $browsers
        if ((Read-Host 'Confirm that the extension is ABSENT in every installed browser profile. Type REMOVED to continue') -cne 'REMOVED') {
            Write-Warning 'Stopped safely. Extension folder and remaining kit files were retained.'
            exit 2
        }
    }
    # The browser has saved its removal before its loaded-unpacked source folder
    # is deleted. Never touch Chromium preference files, including Secure Preferences.
    $remnants = @(Get-TwitterOwnedShortcutRemnants -Browsers $browsers -DataRoot $script:DataRoot)
    Restore-TwitterTaskbarIconBackups -DataRoot $script:DataRoot -Removing $remnants
    if ($remnants.Count -gt 0) {
        Write-Host ('Removing ' + $remnants.Count + ' kit-owned shortcut(s):') -ForegroundColor Yellow
        foreach ($shortcut in $remnants) {
            Write-Host ('  ' + $shortcut)
            Remove-Item -LiteralPath $shortcut -Force -ErrorAction Stop
        }
    }
    Remove-TwitterRestorerArtifacts -DataRoot $script:DataRoot
    Write-Host ''
    Write-Host 'Kit cleanup finished. You confirmed removing/absence of the extension in the browser UI.' -ForegroundColor Green
    Write-Host 'If Twitter Blue Bird Restorer is still listed, open brave://extensions, chrome://extensions or edge://extensions and click Remove.' -ForegroundColor Yellow
    Write-Host 'Close/reopen the browser to see the native X.com branding.'
    Write-Host 'No browser profile or website data was deleted.'
    Write-Host 'You can delete the downloaded ZIP and extracted installer folder yourself.'
} catch {
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'Nothing was force-edited in browser preference files. Re-run the uninstaller after resolving the message.' -ForegroundColor Yellow
    exit 1
}
