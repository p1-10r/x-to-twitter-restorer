Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:KitRoot = Split-Path -Parent $PSScriptRoot
$script:DataRoot = Join-Path $env:LOCALAPPDATA 'TwitterBlueBirdRestorer'
$script:ExtensionRoot = Join-Path $script:DataRoot 'Extension'
$script:PolicyKey = 'HKCU:\Software\Policies\BraveSoftware\Brave'
$script:PolicyStatePath = Join-Path $script:DataRoot 'Policy\installed-policy.json'
$script:PolicyName = 'WebAppInstallForceList'

function Get-KitConfig {
    $file = Join-Path $script:KitRoot 'config.json'
    if (-not (Test-Path -LiteralPath $file)) { throw "Missing config: $file" }
    $config = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
    $repo = [string]$config.github_repo
    if ($repo -and $repo -cnotmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
        throw 'config.json github_repo must be owner/repo.'
    }
    return $config
}
function Find-Brave {
    $names = @(
        (Join-Path $env:PROGRAMFILES 'BraveSoftware\Brave-Browser\Application\brave.exe'),
        (Join-Path ${env:PROGRAMFILES(X86)} 'BraveSoftware\Brave-Browser\Application\brave.exe'),
        (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\Application\brave.exe')
    )
    foreach ($name in $names) { if ($name -and (Test-Path -LiteralPath $name)) { return $name } }
    throw 'Brave executable was not found. Install Brave first.'
}
function Get-PolicyValue([string]$key = $script:PolicyKey) {
    if (-not (Test-Path -LiteralPath $key)) { return $null }
    $v = Get-ItemProperty -LiteralPath $key -Name $script:PolicyName -ErrorAction SilentlyContinue
    if ($null -eq $v) { return $null }
    return [string]$v.($script:PolicyName)
}
function Get-TwitterRelease {
    param([Parameter(Mandatory)][string]$Repository)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $endpoint = "https://api.github.com/repos/$Repository/releases/latest"
    $release = Invoke-RestMethod -Uri $endpoint -Headers @{'User-Agent'='TwitterBlueBirdRestorer/1.4';'Accept'='application/vnd.github+json'} -TimeoutSec 30
    $asset = @($release.assets | Where-Object { $_.name -ceq 'twitter-extension.zip' } | Select-Object -First 1)
    $hash = @($release.assets | Where-Object { $_.name -ceq 'twitter-extension.zip.sha256' } | Select-Object -First 1)
    if ($asset.Count -ne 1 -or $hash.Count -ne 1) { throw 'Latest GitHub release is missing ZIP or SHA256 asset.' }
    $download = Join-Path $env:TEMP ('twitter-ext-' + [guid]::NewGuid().ToString('N') + '.zip')
    $checksum = $download + '.sha256'
    try {
        Invoke-WebRequest -Uri $asset[0].browser_download_url -OutFile $download -UseBasicParsing -TimeoutSec 90
        Invoke-WebRequest -Uri $hash[0].browser_download_url -OutFile $checksum -UseBasicParsing -TimeoutSec 30
        if ((Get-Item -LiteralPath $download).Length -gt 15MB) { throw 'Release archive exceeds 15 MB.' }
        $expected = (Get-Content -LiteralPath $checksum -Raw).Trim().Split(' ')[0].ToLowerInvariant()
        if ($expected -notmatch '^[0-9a-f]{64}$') { throw 'Invalid release checksum.' }
        $actual = (Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($expected -cne $actual) { throw 'GitHub release archive checksum mismatch.' }
        return $download
    } catch {
        if (Test-Path -LiteralPath $download) { Remove-Item -LiteralPath $download -Force }
        throw
    } finally {
        if (Test-Path -LiteralPath $checksum) { Remove-Item -LiteralPath $checksum -Force }
    }
}
function Assert-ExtensionSource([string]$source) {
    $manifestFile = Join-Path $source 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestFile)) { throw 'Extension manifest.json missing.' }
    $manifest = Get-Content -LiteralPath $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.name -cne 'Twitter Blue Bird Restorer' -or [int]$manifest.manifest_version -ne 3) {
        throw 'Unexpected extension in release archive.'
    }
    $siteMatches = @($manifest.content_scripts[0].matches)
    if ($siteMatches -notcontains 'https://x.com/*') { throw 'Release extension does not target x.com.' }
    return [string]$manifest.version
}
function Install-ExtensionSource([string]$source) {
    $newVersion = Assert-ExtensionSource $source
    if (-not (Test-Path -LiteralPath $script:ExtensionRoot)) { New-Item -ItemType Directory -Path $script:ExtensionRoot -Force | Out-Null }
    # Keep a stable location so Brave's one-time Load unpacked registration survives updates.
    Get-ChildItem -LiteralPath $source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $script:ExtensionRoot -Recurse -Force
    }
    Write-Host "Extension files: v$newVersion -> $script:ExtensionRoot" -ForegroundColor Green
}
function Sync-TwitterExtension {
    param([switch]$RequireOnline)
    $config = Get-KitConfig
    $repo = [string]$config.github_repo
    $zip = $null
    $staging = $null
    try {
        if ($repo) {
            try {
                $zip = Get-TwitterRelease -Repository $repo
                $staging = Join-Path $env:TEMP ('twitter-stage-' + [guid]::NewGuid().ToString('N'))
                # Check every entry for absolute paths/traversal before extraction.
                Add-Type -AssemblyName System.IO.Compression.FileSystem
                $archive = [IO.Compression.ZipFile]::OpenRead($zip)
                try {
                    foreach ($entry in $archive.Entries) {
                        if ($entry.FullName.StartsWith('/') -or $entry.FullName.StartsWith('\\') -or $entry.FullName -match '(^|/|\\)\.\.(/|\\|$)' -or $entry.FullName.Contains(':')) {
                            throw 'Unsafe path in release archive.'
                        }
                    }
                } finally { $archive.Dispose() }
                Expand-Archive -LiteralPath $zip -DestinationPath $staging -Force
                Install-ExtensionSource -source $staging
                Write-Host "GitHub release: $repo" -ForegroundColor Green
                return
            } catch {
                if ($RequireOnline) { throw }
                Write-Warning ("GitHub download failed; using bundled extension instead: " + $_.Exception.Message)
            }
        } elseif ($RequireOnline) {
            throw 'GitHub repository not configured. Set github_repo in config.json.'
        }
        $bundled = Join-Path $script:KitRoot 'extension'
        if (-not (Test-Path -LiteralPath $bundled)) { throw 'Bundled extension is not present.' }
        Install-ExtensionSource -source $bundled
    } finally {
        if ($zip -and (Test-Path -LiteralPath $zip)) { Remove-Item -LiteralPath $zip -Force }
        if ($staging -and (Test-Path -LiteralPath $staging)) { Remove-Item -LiteralPath $staging -Recurse -Force }
    }
}
function Get-PolicyIconUrl {
    $config = Get-KitConfig
    if ($config.github_repo) {
        return "https://raw.githubusercontent.com/$($config.github_repo)/main/resources/twitter-pwa.png"
    }
    # Legacy fallback for offline installs. Use GitHub hosting for the larger, optimized icon.
    return 'https://upload.wikimedia.org/wikipedia/commons/7/71/Twitter_Logo_Blue_%282%29.png'
}
function Set-TwitterPolicy {
    $old = Get-PolicyValue
    $machine = Get-PolicyValue 'HKLM:\Software\Policies\BraveSoftware\Brave'
    if ($machine) { throw 'Machine-managed WebAppInstallForceList already exists; left it unchanged.' }
    $state = $null
    if (Test-Path -LiteralPath $script:PolicyStatePath) {
        $state = Get-Content -LiteralPath $script:PolicyStatePath -Raw | ConvertFrom-Json
    }
    if ($old -and ((-not $state) -or $old -cne [string]$state.policyValue)) {
        throw 'A different WebAppInstallForceList policy exists. No changes made.'
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $iconUrl = Get-PolicyIconUrl
    $tempIcon = Join-Path $env:TEMP ('twitter-policy-' + [guid]::NewGuid().ToString('N') + '.png')
    try {
        Invoke-WebRequest -Uri $iconUrl -OutFile $tempIcon -UseBasicParsing -TimeoutSec 40
        if ((Get-Item -LiteralPath $tempIcon).Length -gt 2MB) { throw 'Policy icon too large.' }
        Add-Type -AssemblyName System.Drawing
        $img = [Drawing.Image]::FromFile($tempIcon)
        try {
            if ($img.Width -ne $img.Height) { throw 'Policy icon is not square.' }
            if ($img.RawFormat.Guid -ne [Drawing.Imaging.ImageFormat]::Png.Guid) { throw 'Policy icon is not PNG.' }
        } finally { $img.Dispose() }
        $sha = (Get-FileHash -LiteralPath $tempIcon -Algorithm SHA256).Hash.ToLowerInvariant()
        $entry = [ordered]@{
            url='https://x.com/'; default_launch_container='window'; create_desktop_shortcut=$true
            custom_name='Twitter'; custom_icon=[ordered]@{url=$iconUrl;hash=$sha}
        }
        $value = ConvertTo-Json -InputObject @($entry) -Depth 8 -Compress
        if ($old -ceq $value) { Write-Host 'Brave policy is already current.'; return }
        $stateDir = Split-Path -Parent $script:PolicyStatePath
        New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
        # Replaces only policy values proven to have been written by an earlier version of this kit.
        try {
            New-Item -Path $script:PolicyKey -Force | Out-Null
            if ($old) { Remove-ItemProperty -LiteralPath $script:PolicyKey -Name $script:PolicyName -ErrorAction Stop }
            New-ItemProperty -LiteralPath $script:PolicyKey -Name $script:PolicyName -PropertyType String -Value $value -Force | Out-Null
            if ((Get-PolicyValue) -cne $value) { throw 'Policy readback mismatch.' }
            [pscustomobject]@{policyValue=$value;createdAt=(Get-Date).ToString('o')} |
                ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:PolicyStatePath -Encoding UTF8
        } catch {
            if ($old) {
                New-ItemProperty -LiteralPath $script:PolicyKey -Name $script:PolicyName -PropertyType String -Value $old -Force | Out-Null
            } else {
                Remove-ItemProperty -LiteralPath $script:PolicyKey -Name $script:PolicyName -ErrorAction SilentlyContinue
            }
            throw
        }
        Write-Host 'Brave Twitter PWA policy updated.' -ForegroundColor Green
    } finally {
        if (Test-Path -LiteralPath $tempIcon) { Remove-Item -LiteralPath $tempIcon -Force }
    }
}
function Get-TwitterLinks {
    $shell = New-Object -ComObject WScript.Shell
    $paths = @(
        [Environment]::GetFolderPath('Desktop'),
        [Environment]::GetFolderPath('CommonDesktopDirectory'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:PROGRAMDATA 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar')
    )
    $twitterLinks = New-Object 'System.Collections.Generic.List[System.IO.FileInfo]'
    foreach ($folder in $paths) {
        if (-not $folder -or -not (Test-Path -LiteralPath $folder)) { continue }
        foreach ($item in @(Get-ChildItem -LiteralPath $folder -Filter '*.lnk' -File -Recurse -ErrorAction SilentlyContinue)) {
            if ($item.BaseName -notmatch '^Twitter(?:\s*\(\d+\))?$') { continue }
            $link = $shell.CreateShortcut($item.FullName)
            if (([string]$link.TargetPath) -match '(?i)brave|chrome_proxy') { $twitterLinks.Add($item) }
        }
    }
    return $twitterLinks.ToArray()
}
function Ensure-TwitterDesktopShortcut {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $dest = Join-Path $desktop 'Twitter.lnk'
    $links = @(Get-TwitterLinks)
    if (-not (Test-Path -LiteralPath $dest)) {
        $source = $links | Where-Object { $_.DirectoryName -ne $desktop } | Select-Object -First 1
        if ($source) { Copy-Item -LiteralPath $source.FullName -Destination $dest }
    }
    if (Test-Path -LiteralPath $dest) {
        $shell = New-Object -ComObject WScript.Shell
        $link = $shell.CreateShortcut($dest)
        if ($link.TargetPath -match '(?i)brave|chrome_proxy') {
            $icon = Join-Path $script:DataRoot 'icons\twitter-large.ico'
            New-Item -ItemType Directory -Path (Split-Path -Parent $icon) -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $script:KitRoot 'resources\twitter-large.ico') -Destination $icon -Force
            $link.IconLocation = $icon + ',0'
            $link.Save()
            Write-Host "Twitter desktop shortcut: $dest" -ForegroundColor Green
            return $true
        }
        Write-Warning 'Twitter.lnk already exists but is not a Brave PWA shortcut; left it unchanged.'
    }
    return $false
}

function Remove-OwnedPolicyForFreshInstall {
    $current = Get-PolicyValue
    if (-not $current) { return $false }
    if (-not (Test-Path -LiteralPath $script:PolicyStatePath)) { throw 'Found a policy without matching kit state. No changes made.' }
    $state = Get-Content -LiteralPath $script:PolicyStatePath -Raw | ConvertFrom-Json
    if ($current -cne [string]$state.policyValue) { throw 'Existing policy has been modified externally. No changes made.' }
    Remove-ItemProperty -LiteralPath $script:PolicyKey -Name $script:PolicyName -ErrorAction Stop
    # Retain the ownership record. If interrupted, rerunning Setup can recover.
    Write-Host 'Temporarily removed owned Twitter PWA policy.' -ForegroundColor Yellow
    return $true
}
function Close-BraveGracefully {
    $processes = @(Get-Process -Name brave -ErrorAction SilentlyContinue)
    if ($processes.Count -gt 0) {
        foreach ($p in $processes) {
            try { if ($p.MainWindowHandle -ne [IntPtr]::Zero) { [void]$p.CloseMainWindow() } } catch { }
        }
        $limit = (Get-Date).AddSeconds(20)
        while ((Get-Process -Name brave -ErrorAction SilentlyContinue) -and (Get-Date) -lt $limit) {
            Start-Sleep -Seconds 1
        }
        if (Get-Process -Name brave -ErrorAction SilentlyContinue) {
            throw 'Brave is still running. Exit Brave completely (including tray/background) and run Setup again.'
        }
    }
}
function Restart-BraveGracefully([string]$brave,[string]$page) {
    Close-BraveGracefully
    Start-Process -FilePath $brave -ArgumentList $page
}
