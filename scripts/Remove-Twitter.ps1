# Undo only the policy managed by this kit; never clear unrelated policies.
[CmdletBinding()]
param([ValidateSet('Auto','Brave','Chrome','Edge')][string]$Browser = 'Auto')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Twitter.Common.ps1')
try {
    $selected = Select-TwitterBrowser -Requested $Browser
    Initialize-TwitterBrowser $selected
    $current = Get-PolicyValue
    if (-not (Test-Path -LiteralPath $script:PolicyStatePath)) {
        Write-Host 'No owned Twitter policy record. No changes.'
        return
    }
    $owned = Get-Content -LiteralPath $script:PolicyStatePath -Raw | ConvertFrom-Json
    if ($current -and $current -cne [string]$owned.policyValue) {
        throw 'Policy changed externally. It was left untouched.'
    }
    if ($current) { Remove-ItemProperty -LiteralPath $script:PolicyKey -Name $script:PolicyName }
    Remove-Item -LiteralPath $script:PolicyStatePath -Force
    Write-Host 'Removed owned Twitter PWA policy. Restart the selected browser to finish.' -ForegroundColor Green
    Write-Host 'The installed PWA may disappear when the force-install policy is removed.'
} catch {
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
