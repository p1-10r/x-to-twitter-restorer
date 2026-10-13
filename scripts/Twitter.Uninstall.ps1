# Shared, non-interactive uninstall helpers. Windows PowerShell 5.1 compatible.
# Only remove values provably managed by this kit, never browser profiles.
function Get-TwitterOwnedPolicyRecord {
    param([Parameter(Mandatory)][object]$Browser)
    Initialize-TwitterBrowser $Browser
    $policy = Get-PolicyValue
    $recordPath = $script:PolicyStatePath
    if (-not (Test-Path -LiteralPath $recordPath -PathType Leaf)) {
        return [pscustomobject]@{Browser=$Browser;Owned=$false;Current=$policy;StatePath=$recordPath}
    }
    $record = Get-Content -LiteralPath $recordPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    $saved = [string](Get-TwitterOptionalProperty -Object $record -Name 'policyValue')
    if (-not $saved -or ($policy -and $policy -cne $saved)) {
        throw ('Policy for ' + $Browser.DisplayName + ' was changed outside Twitter Restorer. Refusing to remove it.')
    }
    return [pscustomobject]@{Browser=$Browser;Owned=$true;Current=$policy;StatePath=$recordPath}
}
function Remove-TwitterOwnedPolicyValue {
    param([Parameter(Mandatory)][object]$Record)
    if (-not $Record.Owned) { return $false }
    Initialize-TwitterBrowser $Record.Browser
    # Recheck just before modification, not only when the preview was shown.
    $fresh = Get-TwitterOwnedPolicyRecord -Browser $Record.Browser
    if (-not $fresh.Owned) { throw 'Ownership record disappeared. No policy changed.' }
    if (-not $fresh.Current) { return $false }
    Remove-ItemProperty -LiteralPath $script:PolicyKey -Name $script:PolicyName -ErrorAction Stop
    if (Get-PolicyValue) { throw ('Could not clear owned policy for ' + $Record.Browser.DisplayName) }
    Write-Host ('Removed managed PWA policy: ' + $Record.Browser.DisplayName) -ForegroundColor Green
    return $true
}
function Test-TwitterUpdaterTaskOwned {
    param([AllowNull()][object]$Task, [Parameter(Mandatory)][string]$DataRoot)
    if ($null -eq $Task) { return $false }
    $actionList = @($Task.Actions)
    if ($actionList.Count -ne 1) { return $false }
    $exe = [string]$actionList[0].Execute
    $args = [string]$actionList[0].Arguments
    if ($exe -notmatch '(?i)(^|[\\/])powershell\.exe$') { return $false }
    $expected = Join-Path $DataRoot 'Updater\Update-Twitter.ps1'
    # Compare the exact -File argument; do not take over a task with the same name.
    $match = [regex]::Match($args,'(?i)(?:^|\s)-File\s+(?:"([^"]+)"|(\S+))')
    if (-not $match.Success) { return $false }
    $fileArg = if ($match.Groups[1].Success) { $match.Groups[1].Value } else { $match.Groups[2].Value }
    try { return [string]::Equals([IO.Path]::GetFullPath($fileArg),[IO.Path]::GetFullPath($expected),[StringComparison]::OrdinalIgnoreCase) }
    catch { return $false }
}
function Get-TwitterOwnedShortcutRemnants {
    # Do not delete all Twitter shortcuts. Only our own browser PWA links with
    # an icon hosted inside the dedicated TwitterBlueBirdRestorer directory.
    param([Parameter(Mandatory)][object[]]$Browsers,[Parameter(Mandatory)][string]$DataRoot)
    $folders = @(
        [Environment]::GetFolderPath('Desktop'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar')
    )
    $results = New-Object 'System.Collections.Generic.List[string]'
    $shell = New-Object -ComObject WScript.Shell
    foreach ($browser in $Browsers) {
        Initialize-TwitterBrowser $browser
        foreach ($folder in $folders) {
            if (-not (Test-Path -LiteralPath $folder -PathType Container)) { continue }
            foreach ($item in @(Get-ChildItem -LiteralPath $folder -Filter '*.lnk' -File -Recurse -ErrorAction SilentlyContinue)) {
                if ($item.BaseName -notmatch '^(?i:Twitter|X|x\.com)(?: \((?i:Brave|Chrome|Google Chrome|Edge|Microsoft Edge|[0-9]+)\))?$') { continue }
                try {
                    $link = $shell.CreateShortcut($item.FullName)
                    if ([string]$link.TargetPath -notmatch $browser.AppPathMatch) { continue }
                    $arg = [string]$link.Arguments
                    if ($arg -notmatch '(?i)(?:^|\s)--app-id=[a-p]{32}(?:\s|$)' -and
                        $arg -notmatch '(?i)(?:^|\s)--app=https://x\.com(?:/|\s|$)') { continue }
                    $icon = [string]$link.IconLocation
                    if ($icon -notmatch '(?i)TwitterBlueBirdRestorer[\\/](?:icons|TaskbarIcon[\\/]icons)[\\/]') { continue }
                    if (-not $results.Contains($item.FullName)) { $results.Add($item.FullName) }
                } catch { Write-Warning ('Could not inspect shortcut: ' + $item.FullName) }
            }
        }
    }
    return $results.ToArray()
}
function Get-TwitterBrowserExtensionRegistrations {
    param([Parameter(Mandatory)][object]$Browser)
    Initialize-TwitterBrowser $Browser
    $found = New-Object 'System.Collections.Generic.List[object]'
    foreach ($profile in @(Get-TwitterProfileCandidates)) {
        $status = Get-TwitterExtensionStatus -Profile $profile
        if ($status.RegistrationPresent -and $status.Path) {
            try {
                $actual = [IO.Path]::GetFullPath([string]$status.Path).TrimEnd('\')
                $expected = [IO.Path]::GetFullPath([string]$script:ExtensionRoot).TrimEnd('\')
                if ([string]::Equals($actual,$expected,[StringComparison]::OrdinalIgnoreCase)) { $found.Add($status) }
            } catch { }
        }
    }
    return $found.ToArray()
}
function Restore-TwitterTaskbarIconBackups {
    param([Parameter(Mandatory)][string]$DataRoot, [Parameter(Mandatory)][string[]]$Removing)
    $pinFolder = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
    $backupRoot = Join-Path $DataRoot 'TaskbarIcon\backups'
    foreach ($browserId in @('brave','chrome','edge')) {
        $file = Join-Path $DataRoot ('TaskbarIcon\shortcut-backups-' + $browserId + '.json')
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        $state = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        foreach ($record in @($state.shortcuts)) {
            $link = [string]$record.shortcut
            $backup = [string]$record.backup
            $isPinned = [string]::Equals([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($link)),[IO.Path]::GetFullPath($pinFolder).TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase)
            $isOwnBackup = [IO.Path]::GetFullPath($backup).StartsWith(([IO.Path]::GetFullPath($backupRoot).TrimEnd('\') + '\'),[StringComparison]::OrdinalIgnoreCase)
            if (-not $isPinned -or -not $isOwnBackup) { throw 'Unexpected taskbar backup path: ' + $link }
            if (($Removing -contains $link) -or -not (Test-Path -LiteralPath $link -PathType Leaf)) { continue }
            if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) { throw 'Taskbar shortcut backup is missing: ' + $backup }
            $shell = New-Object -ComObject WScript.Shell
            $current = $shell.CreateShortcut($link)
            if ([string]$current.IconLocation -match '(?i)TwitterBlueBirdRestorer[\\/]') {
                Copy-Item -LiteralPath $backup -Destination $link -Force -ErrorAction Stop
                Write-Host ('Restored original pinned shortcut: ' + $link) -ForegroundColor Green
            }
        }
    }
}

function Remove-TwitterRestorerArtifacts {
    param([Parameter(Mandatory)][string]$DataRoot)
    $expected = Join-Path $env:LOCALAPPDATA 'TwitterBlueBirdRestorer'
    if (-not [string]::Equals([IO.Path]::GetFullPath($DataRoot),[IO.Path]::GetFullPath($expected),[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Unexpected application data path. Refusing recursive deletion.'
    }
    if (-not (Test-Path -LiteralPath $DataRoot)) { return }
    $rootItem = Get-Item -LiteralPath $DataRoot -Force
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Application data folder is a junction/symlink. Left untouched.' }
    # Never delete arbitrary other files. Only the known dedicated kit paths.
    foreach ($directory in @('Extension','Updater','icons','TaskbarIcon','DesktopShortcutBackups')) {
        $target = Join-Path $DataRoot $directory
        if (Test-Path -LiteralPath $target) {
            $item = Get-Item -LiteralPath $target -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                Write-Warning ('Skipping linked directory: ' + $target)
                continue
            }
            $nestedLinks = @(Get-ChildItem -LiteralPath $target -Recurse -Force -ErrorAction Stop |
                Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 })
            if ($nestedLinks.Count -gt 0) { Write-Warning ('Skipping directory with junction/symlink inside: ' + $target); continue }
            Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
            Write-Host ('Removed: ' + $target)
        }
    }
    $policyFolder = Join-Path $DataRoot 'Policy'
    if (Test-Path -LiteralPath $policyFolder) {
        $policyItem = Get-Item -LiteralPath $policyFolder -Force
        if (($policyItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Policy folder is a junction/symlink. Left untouched.' }
        foreach ($browserId in @('brave','chrome','edge')) {
            $fileName = if ($browserId -eq 'brave') { 'installed-policy.json' } else { 'installed-policy-' + $browserId + '.json' }
            $file = Join-Path $policyFolder $fileName
            if (Test-Path -LiteralPath $file -PathType Leaf) { Remove-Item -LiteralPath $file -Force }
        }
        if (@(Get-ChildItem -LiteralPath $policyFolder -Force -ErrorAction Stop).Count -eq 0) { Remove-Item -LiteralPath $policyFolder -Force }
    }
    foreach ($name in @('config.json','pending-browser-restart.txt','update.log')) {
        $file = Join-Path $DataRoot $name
        if (Test-Path -LiteralPath $file -PathType Leaf) { Remove-Item -LiteralPath $file -Force }
    }
    if (@(Get-ChildItem -LiteralPath $DataRoot -Force -ErrorAction Stop).Count -eq 0) {
        Remove-Item -LiteralPath $DataRoot -Force
        Write-Host 'Twitter Restorer application data folder removed.' -ForegroundColor Green
    } else {
        Write-Warning ('Unknown files remain in ' + $DataRoot + '. Left them intact for safety.')
    }
}

# Browser-side installation records must only be removed through browser UI.
# This function is informational and deliberately never writes browser preferences.
function Show-TwitterExtensionManualRemovalInstructions {
    param([Parameter(Mandatory)][object[]]$Browsers)
    Write-Host ''
    Write-Host 'IMPORTANT: Unpacked extensions are NOT removed just by deleting the installer files.' -ForegroundColor Yellow
    Write-Host 'MANUAL EXTENSION REMOVAL - follow these steps if the extension is still shown:' -ForegroundColor Yellow
    foreach ($browser in $Browsers) {
        if (-not (Find-BrowserExecutable $browser)) { continue }
        Write-Host ('  ' + $browser.DisplayName + ': ' + $browser.Scheme + '://extensions')
    }
    Write-Host '  1. Open the extensions URL above in the corresponding browser.'
    Write-Host '  2. Find the extension card named "Twitter Blue Bird Restorer".'
    Write-Host '  3. Click Remove (trash/remove button), then confirm Remove in the dialog.'
    Write-Host '     Turning the ON/OFF toggle OFF is NOT removal.' -ForegroundColor Yellow
    Write-Host '  4. Switch browser profiles (profile/avatar menu) and repeat in EVERY profile.'
    Write-Host '  5. Reload the extensions page: the Twitter Blue Bird Restorer card must be GONE.'
    Write-Host '  6. Fully exit the browser so it can save its settings; then continue here.'
    Write-Host 'If Remove is blocked by a managed policy, restart the browser after this tool'
    Write-Host 'clears its owned policies. Never edit Preferences/Secure Preferences by hand.'
    Write-Host 'Do not type REMOVED until ALL affected browsers and profiles have been checked.' -ForegroundColor Yellow
    Write-Host ''
}
