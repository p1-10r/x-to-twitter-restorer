# Elevate only after preserving the originating Windows user identity.
# Browser-specific policy and PWA registration live under HKCU, so elevating as a
# different admin account would otherwise silently configure the WRONG profile.
function Invoke-TwitterElevation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string]$OriginalSid,
        [Parameter(Mandatory)][string[]]$RelaunchArguments
    )
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if ($identity.User.Value -cne $OriginalSid) {
        throw 'Elevation switched Windows users. No settings were changed. Sign in as a Windows administrator using the same account and retry.'
    }
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host 'Administrator privileges confirmed.' -ForegroundColor DarkGreen
        return $false
    }
    $powershell = Join-Path $PSHOME 'powershell.exe'
    $safeScript = $ScriptPath.Replace('"','')
    $args = '-NoProfile -ExecutionPolicy Bypass -File "' + $safeScript + '" -OriginalSid ' + $OriginalSid + ' ' + ($RelaunchArguments -join ' ')
    Write-Host 'Requesting Windows administrator approval (UAC)...' -ForegroundColor Yellow
    try {
        $child = Start-Process -FilePath $powershell -ArgumentList $args -Verb RunAs -Wait -PassThru -ErrorAction Stop
    } catch {
        throw ('Administrator approval was cancelled or could not be requested: ' + $_.Exception.Message)
    }
    if ($child.ExitCode -ne 0) {
        throw ('Elevated Twitter Restorer exited with code ' + $child.ExitCode + '. Check the administrator PowerShell window for the exact error.')
    }
    Write-Host 'Elevated setup completed.' -ForegroundColor Green
    return $true
}
