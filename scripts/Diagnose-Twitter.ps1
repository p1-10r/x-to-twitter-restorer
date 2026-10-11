# Read-only diagnostics. Does not display browser preference contents or tokens.
[CmdletBinding()]
param([ValidateSet('Auto','Brave','Chrome','Edge')][string]$Browser = 'Auto')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Twitter.Common.ps1')
try {
    $selected = Select-TwitterBrowser -Requested $Browser
    Initialize-TwitterBrowser $selected
    Write-Host ('Browser: ' + $selected.DisplayName) -ForegroundColor Cyan
    Write-Host ('Stable extension folder: ' + $script:ExtensionRoot)
    Write-Host ('Browser user-data folder: ' + (Get-BrowserProfileRoot))
    foreach ($profile in @(Get-TwitterProfileCandidates)) {
        $check = Get-TwitterExtensionStatus -Profile $profile
        Write-Host ('Profile: {0} | Installed: {1} | Records: {2} | Source: {3}' -f $profile,$check.Installed,$check.RecordsSeen,$check.Source)
        $savedEnablement = if ($check.EnabledVerified) { 'True (state=1)' } elseif ($check.Disabled) { 'False (state=0)' } else { 'Unknown' }
        Write-Host ('  Registered: ' + $check.RegistrationPresent + ' | Enabled in saved prefs: ' + $savedEnablement)
        if ($check.StateInferred) { Write-Host '  Install readiness: Inferred from matching source, ID and version; live ON state not independently verified.' -ForegroundColor Yellow }
        Write-Host ('  Saved states: ' + (@($check.StateDetails) -join ', '))
        Write-Host ('  Reason: ' + $check.Reason)
        if ($check.Id) { Write-Host ('  Extension ID: ' + $check.Id) }
        if ($check.Path) { Write-Host ('  Registered path: ' + $check.Path) }
    }
    Write-Host 'Missing state does not prove disabled. Inferred readiness requires matching registration and current source; browser UI is authoritative for the live ON toggle.' -ForegroundColor Yellow
    Write-Host 'Desktop Twitter PWA shortcuts:'
    $shell = New-Object -ComObject WScript.Shell
    $links = @(Get-TwitterDesktopLinks)
    if ($links.Count -eq 0) { Write-Host '  No matching PWA shortcuts found.' }
    foreach ($entry in $links) {
        $shortcut = $shell.CreateShortcut($entry.FullName)
        Write-Host ('  ' + $entry.FullName)
        Write-Host ('  IconLocation: ' + $shortcut.IconLocation)
    }
    Write-Host 'Done. No files, profiles, browser policies, or shortcuts were modified.' -ForegroundColor Green
} catch {
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
