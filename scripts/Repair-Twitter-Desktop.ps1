# Repair only existing desktop PWA shortcut icons. No browser restart or registry changes.
[CmdletBinding()]
param([ValidateSet('Auto','Brave','Chrome','Edge')][string]$Browser = 'Auto')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Twitter.Common.ps1')
try {
    $selected = Select-TwitterBrowser -Requested $Browser
    Initialize-TwitterBrowser $selected
    Write-Host ('Checking desktop shortcuts for ' + $selected.DisplayName) -ForegroundColor Cyan
    $fixed = Repair-TwitterDesktopIcons
    if ($fixed -eq 0) {
        Write-Warning 'No matching PWA desktop shortcuts found. Create one from the browser apps page first.'
    } else {
        Write-Host ('Repaired ' + $fixed + ' shortcut(s). If white remains, refresh desktop or sign out/in to clear icon cache.') -ForegroundColor Green
    }
} catch {
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
