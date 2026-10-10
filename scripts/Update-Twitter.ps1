# Download only the latest published extension; do not terminate a browsing session.
[CmdletBinding()]
param([switch]$Silent)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Twitter.Common.ps1')
try {
    $config = Get-KitConfig
    if (-not $config.github_repo) { if (-not $Silent) { Write-Warning 'GitHub repo not configured.' }; return }
    $oldVersion = ''
    $manifest = Join-Path $script:ExtensionRoot 'manifest.json'
    if (Test-Path -LiteralPath $manifest) {
        $oldVersion = [string](Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json).version
    }
    Sync-TwitterExtension -RequireOnline
    $newVersion = [string](Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json).version
    if ($newVersion -cne $oldVersion) {
        New-Item -ItemType Directory -Path $script:DataRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:DataRoot 'pending-browser-restart.txt') -Value ("Extension updated $oldVersion -> $newVersion. Reload the extension in your browser to load new files.")
        Add-Content -LiteralPath (Join-Path $script:DataRoot 'update.log') -Value ((Get-Date).ToString('o') + " updated $oldVersion to $newVersion")
        if (-not $Silent) { Write-Host "Updated to $newVersion. Reload the extension in your browser to activate." -ForegroundColor Green }
    } elseif (-not $Silent) { Write-Host "Extension up to date: $newVersion" }
} catch {
    if (-not (Test-Path -LiteralPath $script:DataRoot)) { New-Item -ItemType Directory -Path $script:DataRoot -Force | Out-Null }
    Add-Content -LiteralPath (Join-Path $script:DataRoot 'update.log') -Value ((Get-Date).ToString('o') + ' ERROR: ' + $_.Exception.Message)
    if (-not $Silent) { Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red }
    exit 1
}
