# One-time migration for v1.5.12 and older. Preserves installed PWA and browser data.
[CmdletBinding()]
param([ValidateSet('Auto','Brave','Chrome','Edge')][string]$Browser = 'Auto')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Twitter.Common.ps1')
try {
    $selected = Select-TwitterBrowser -Requested $Browser
    Initialize-TwitterBrowser $selected
    Write-Host ('Target browser: ' + $selected.DisplayName) -ForegroundColor Cyan
    $current = Get-PolicyValue
    if (-not $current) {
        throw 'No Twitter policy found. No changes made; run the full installer if needed.'
    }
    $planned = @(Get-TwitterDuplicateDesktopShortcuts)
    Write-Host 'Will disable automatic desktop shortcut creation in the kit-owned browser policy.'
    Write-Host 'No app uninstall, profile change, extension change, or site-data deletion.'
    if ($planned.Count -gt 0) {
        Write-Host 'Extra shortcuts to MOVE into AppData backup:' -ForegroundColor Yellow
        foreach ($item in $planned) { Write-Host ('  ' + $item.FullName) }
    } else {
        Write-Host 'No identical numbered Twitter desktop shortcuts to back up.'
    }
    if ((Read-Host 'To apply this repair type FIX (anything else cancels)') -cne 'FIX') {
        Write-Host 'Cancelled. No changes made.'
        return
    }
    $policyChanged = Disable-OwnedTwitterPolicyDesktopShortcut
    $moved = Backup-TwitterDuplicateDesktopShortcuts
    Write-Host ('Done. Numbered duplicates backed up: ' + $moved) -ForegroundColor Green
    if ($policyChanged) { Write-Host 'Fully restart the selected browser once so it reloads the updated policy.' -ForegroundColor Yellow }
} catch {
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
