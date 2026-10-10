# Standalone bootstrap: direct .ps1 runs pause; the .cmd wrapper uses -NoPause and handles the prompt.
[CmdletBinding()]
param([string]$Repository = 'p1-10r/x-to-twitter-restorer', [ValidateSet('Auto','Brave','Chrome','Edge')][string]$Browser = 'Auto', [switch]$NoPause)
$ErrorActionPreference = 'Stop'
$script:BootstrapExitCode = 0
# Validate repository within the try so direct execution can display errors before closing.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$cache = Join-Path $env:LOCALAPPDATA 'TwitterBlueBirdRestorer\Kit'
$temp = Join-Path $env:TEMP ('twitter-bootstrap-' + [guid]::NewGuid().ToString('N'))
try {
    $Repository = $Repository.Trim()
    if ($Repository -match '^[A-Za-z0-9_.-]+$') { $Repository = 'p1-10r/' + $Repository }
    if ($Repository -cnotmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Use repo or owner/repo.' }
    Write-Host ('Fetching latest release from: ' + $Repository) -ForegroundColor Cyan
    try {
        $latest = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository/releases/latest" -Headers @{'User-Agent'='TwitterBlueBirdRestorer/1.4'} -TimeoutSec 30
    } catch {
        throw ('GitHub Release cannot be downloaded yet. Publish the repository with Start-Twitter-Publish.cmd, wait for Actions, then retry. Details: ' + $_.Exception.Message)
    }
    $kit = @($latest.assets | Where-Object { $_.name -ceq 'twitter-restorer-kit.zip' } | Select-Object -First 1)
    $hash = @($latest.assets | Where-Object { $_.name -ceq 'twitter-restorer-kit.zip.sha256' } | Select-Object -First 1)
    if ($kit.Count -ne 1 -or $hash.Count -ne 1) { throw 'No release ZIP found. Publish code with Start-Twitter-Publish.cmd and wait for GitHub Actions to finish.' }
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    $archive = Join-Path $temp 'kit.zip'
    $hashFile = Join-Path $temp 'kit.sha256'
    Invoke-WebRequest -Uri $kit[0].browser_download_url -OutFile $archive -UseBasicParsing -TimeoutSec 120
    Invoke-WebRequest -Uri $hash[0].browser_download_url -OutFile $hashFile -UseBasicParsing -TimeoutSec 30
    if ((Get-Item -LiteralPath $archive).Length -gt 40MB) { throw 'Kit archive is unexpectedly large.' }
    $expected = (Get-Content -LiteralPath $hashFile -Raw).Trim().Split(' ')[0].ToLowerInvariant()
    $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($expected -notmatch '^[0-9a-f]{64}$' -or $expected -cne $actual) { throw 'Invalid GitHub release ZIP checksum.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    try {
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName.StartsWith('/') -or $entry.FullName.StartsWith('\\') -or $entry.FullName -match '(^|/|\\)\.\.(/|\\|$)' -or $entry.FullName.Contains(':')) { throw 'Unsafe ZIP entry path.' }
        }
    } finally { $zip.Dispose() }
    $expand = Join-Path $temp 'extracted'
    Expand-Archive -LiteralPath $archive -DestinationPath $expand -Force
    $entrypoint = Join-Path $expand 'scripts\Install-Twitter.ps1'
    if (-not (Test-Path -LiteralPath $entrypoint)) { throw 'Installer is missing from the GitHub kit.' }
    $manifestFile = Join-Path $expand 'extension\manifest.json'
    $manifest = Get-Content -LiteralPath $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.name -cne 'Twitter Blue Bird Restorer') { throw 'Unexpected kit contents.' }
    New-Item -ItemType Directory -Path $cache -Force | Out-Null
    Get-ChildItem -LiteralPath $expand -Force | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $cache -Recurse -Force }
    $config = Get-Content -LiteralPath (Join-Path $cache 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $config.github_repo = $Repository
    [System.IO.File]::WriteAllText((Join-Path $cache 'config.json'), ($config | ConvertTo-Json -Depth 5), ([System.Text.UTF8Encoding]::new($false)))
    Write-Host ('Downloaded and verified latest release: ' + [string]$manifest.version) -ForegroundColor Green
    & (Join-Path $cache 'scripts\Install-Twitter.ps1') -FreshPwa -Browser $Browser
    if (-not $?) { throw 'Setup did not complete successfully.' }
} catch {
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host ('At: ' + [string]$_.InvocationInfo.PositionMessage) -ForegroundColor DarkYellow
    $script:BootstrapExitCode = 1
} finally {
    try { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force } }
    catch { Write-Warning ('Temporary download cleanup failed: ' + $_.Exception.Message) }
    if (-not $NoPause -and [Environment]::UserInteractive) {
        try { $null = Read-Host 'Press Enter to close this window (or inspect the output first)' } catch { }
    }
}
if ($script:BootstrapExitCode -eq 1) { exit 1 }

