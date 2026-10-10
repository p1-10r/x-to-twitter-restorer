Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:KitRoot = Split-Path -Parent $PSScriptRoot
$script:DataRoot = Join-Path $env:LOCALAPPDATA 'TwitterBlueBirdRestorer'
$script:ExtensionRoot = Join-Path $script:DataRoot 'Extension'
$script:PolicyKey = $null
$script:SelectedBrowser = $null
$script:PolicyStatePath = $null
$script:PolicyName = 'WebAppInstallForceList'

# Browser selection is explicit if Windows' HTTPS default is unsupported or unknown.
function Get-BrowserDefinition([string]$Id) {
    switch ($Id.ToLowerInvariant()) {
        'brave' { return [pscustomobject]@{
            Id='brave'; DisplayName='Brave'; Process='brave'; Executable='brave.exe';
            Subpath='BraveSoftware\Brave-Browser\Application\brave.exe';
            PolicyKey='HKCU:\Software\Policies\BraveSoftware\Brave';
            MachinePolicyKey='HKLM:\Software\Policies\BraveSoftware\Brave';
            Scheme='brave'; AppPathMatch='(?i)BraveSoftware[\\/]Brave-Browser[\\/]Application[\\/](?:brave|chrome_proxy)\.exe'
        } }
        'chrome' { return [pscustomobject]@{
            Id='chrome'; DisplayName='Google Chrome'; Process='chrome'; Executable='chrome.exe';
            Subpath='Google\Chrome\Application\chrome.exe';
            PolicyKey='HKCU:\Software\Policies\Google\Chrome';
            MachinePolicyKey='HKLM:\Software\Policies\Google\Chrome';
            Scheme='chrome'; AppPathMatch='(?i)Google[\\/]Chrome[\\/]Application[\\/](?:chrome|chrome_proxy)\.exe'
        } }
        'edge' { return [pscustomobject]@{
            Id='edge'; DisplayName='Microsoft Edge'; Process='msedge'; Executable='msedge.exe';
            Subpath='Microsoft\Edge\Application\msedge.exe';
            PolicyKey='HKCU:\Software\Policies\Microsoft\Edge';
            MachinePolicyKey='HKLM:\Software\Policies\Microsoft\Edge';
            Scheme='edge'; AppPathMatch='(?i)Microsoft[\\/]Edge[\\/]Application[\\/](?:msedge|msedge_proxy)\.exe'
        } }
        default { throw "Unsupported browser: $Id. Choose Chrome, Edge, or Brave." }
    }
}
function Find-BrowserExecutable([object]$Browser) {
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    foreach ($parent in @($env:PROGRAMFILES,${env:PROGRAMFILES(X86)},$env:LOCALAPPDATA)) {
        if (-not [string]::IsNullOrWhiteSpace($parent)) { $candidates.Add((Join-Path $parent $Browser.Subpath)) }
    }
    # Edge sometimes uses Program Files (x86), and Chrome supports per-user installs.
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}
function Get-DefaultBrowserId {
    $root = 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https'
    # Windows 11 25H2 can update UserChoiceLatest without updating UserChoice.
    foreach ($leaf in @('UserChoiceLatest','UserChoice')) {
        $key = Join-Path $root $leaf
        $record = Get-ItemProperty -LiteralPath $key -Name ProgId -ErrorAction SilentlyContinue
        if ($null -eq $record) { continue }
        $progId = [string]$record.ProgId
        if ($progId -match '(?i)^BraveHTML') { return 'brave' }
        if ($progId -match '(?i)^ChromeHTML') { return 'chrome' }
        if ($progId -match '(?i)^MSEdgeHTM') { return 'edge' }
        # Do not fall back to an old UserChoice when the latest choice exists but is unsupported.
        if ($progId) { return $null }
    }
    return $null
}
function Select-TwitterBrowser([string]$Requested = 'Auto') {
    if ($Requested -and $Requested -ne 'Auto') {
        $result = Get-BrowserDefinition $Requested
        if (-not (Find-BrowserExecutable $result)) { throw ($result.DisplayName + ' is not installed.') }
        return $result
    }
    $defaultId = Get-DefaultBrowserId
    if ($defaultId) {
        $result = Get-BrowserDefinition $defaultId
        if (Find-BrowserExecutable $result) {
            Write-Host ('Windows default HTTPS browser: ' + $result.DisplayName) -ForegroundColor Cyan
            return $result
        }
    }
    $available = @(@('brave','chrome','edge') | ForEach-Object {
        $candidate = Get-BrowserDefinition $_
        if (Find-BrowserExecutable $candidate) { $candidate }
    })
    if ($available.Count -eq 0) { throw 'No supported browser installed. Install Chrome, Edge, or Brave first.' }
    Write-Host 'Could not determine a supported default browser. Select the target browser:' -ForegroundColor Yellow
    for ($i = 0; $i -lt $available.Count; $i++) {
        Write-Host ('  ' + ($i+1) + '. ' + $available[$i].DisplayName)
    }
    $choice = Read-Host 'Browser number (Enter cancels)'
    if ($choice -notmatch '^\d+$') { throw 'Browser selection cancelled.' }
    $index = [int]$choice - 1
    if ($index -lt 0 -or $index -ge $available.Count) { throw 'Invalid browser selection.' }
    return $available[$index]
}
function Initialize-TwitterBrowser([object]$Browser) {
    $script:SelectedBrowser = $Browser
    $script:PolicyKey = $Browser.PolicyKey
    # Keep v1.4.x Brave state in its original location for safe upgrades/removal.
    $stateName = if ($Browser.Id -eq 'brave') { 'installed-policy.json' } else { 'installed-policy-' + $Browser.Id + '.json' }
    $script:PolicyStatePath = Join-Path $script:DataRoot ('Policy\' + $stateName)
}

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
    # Compatibility with existing scripts; browser selection now happens in Install-Twitter.ps1.
    $spec = Get-BrowserDefinition 'brave'
    $file = Find-BrowserExecutable $spec
    if (-not $file) { throw 'Brave not installed.' }
    return $file
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
    # Keep a stable location so a browser's one-time Load unpacked registration survives updates.
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
    $machine = Get-PolicyValue $script:SelectedBrowser.MachinePolicyKey
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
        if ($old -ceq $value) { Write-Host ($script:SelectedBrowser.DisplayName + ' policy is already current.'); return }
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
        Write-Host ($script:SelectedBrowser.DisplayName + ' Twitter PWA policy updated.') -ForegroundColor Green
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
    $links = New-Object 'System.Collections.Generic.List[System.IO.FileInfo]'
    foreach ($folder in $paths) {
        if (-not $folder -or -not (Test-Path -LiteralPath $folder)) { continue }
        foreach ($item in @(Get-ChildItem -LiteralPath $folder -Filter '*.lnk' -File -Recurse -ErrorAction SilentlyContinue)) {
            if ($item.BaseName -notmatch '(?i)^(?:Twitter|X|x\.com)(?:\s*\([^)]+\))?$') { continue }
            $shortcut = $shell.CreateShortcut($item.FullName)
            if (([string]$shortcut.TargetPath) -match $script:SelectedBrowser.AppPathMatch) { $links.Add($item) }
        }
    }
    return $links.ToArray()
}
function Ensure-TwitterDesktopShortcut {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $dest = Join-Path $desktop 'Twitter.lnk'
    $shell = New-Object -ComObject WScript.Shell
    if (Test-Path -LiteralPath $dest) {
        $old = $shell.CreateShortcut($dest)
        if (([string]$old.TargetPath) -notmatch $script:SelectedBrowser.AppPathMatch) {
            # Do not hijack another browser's Twitter shortcut.
            $dest = Join-Path $desktop ('Twitter (' + $script:SelectedBrowser.DisplayName + ').lnk')
        }
    }
    if (-not (Test-Path -LiteralPath $dest)) {
        $source = @(Get-TwitterLinks | Where-Object { $_.FullName -ne $dest } | Select-Object -First 1)
        if ($source.Count -gt 0) { Copy-Item -LiteralPath $source[0].FullName -Destination $dest }
    }
    if (Test-Path -LiteralPath $dest) {
        $link = $shell.CreateShortcut($dest)
        if (([string]$link.TargetPath) -notmatch $script:SelectedBrowser.AppPathMatch) {
            Write-Warning 'Existing desktop shortcut belongs to another app. Left unchanged.'
            return $null
        }
        $icon = Join-Path $script:DataRoot 'icons\twitter-large.ico'
        New-Item -ItemType Directory -Path (Split-Path -Parent $icon) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:KitRoot 'resources\twitter-large.ico') -Destination $icon -Force
        $link.IconLocation = $icon + ',0'
        $link.Save()
        Write-Host ('Twitter desktop shortcut: ' + $dest) -ForegroundColor Green
        return $dest
    }
    return $null
}
function Get-BrowserTwitterAppRegistrations {
    $uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
    if (-not (Test-Path -LiteralPath $uninstallKey)) { return @() }
    $registrations = New-Object 'System.Collections.Generic.List[object]'
    foreach ($key in @(Get-ChildItem -LiteralPath $uninstallKey -ErrorAction SilentlyContinue)) {
        $properties = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
        if ($null -eq $properties -or -not $properties.PSObject.Properties['DisplayName'] -or -not $properties.PSObject.Properties['UninstallString']) { continue }
        $label = [string]$properties.DisplayName
        if ($label -cnotmatch '^(?i:X|Twitter|x\.com|Twitter - X)$') { continue }
        $uninstall = [string]$properties.UninstallString
        if ($uninstall -notmatch $script:SelectedBrowser.AppPathMatch) { continue }
        $app = [regex]::Match($uninstall, '(?i)(?:^|\s)--uninstall-app-id=([a-p]{32})(?=\s|$)')
        if (-not $app.Success) { continue }
        if ($uninstall -match '(?i)--user-data-dir=') {
            throw "Custom browser profile detected for $label. Remove the PWA manually without deleting browsing data, then retry."
        }
        $profileMatch = [regex]::Match($uninstall, '(?i)(?:^|\s)--profile-directory=(?:"([^"]+)"|([^\s]+))')
        $profile = 'Default'
        if ($profileMatch.Success) {
            if ($profileMatch.Groups[1].Success) { $profile = $profileMatch.Groups[1].Value }
            else { $profile = $profileMatch.Groups[2].Value }
        }
        if ($profile -cnotmatch '^[A-Za-z0-9 _.-]{1,100}$' -or $profile -match '^\.{1,2}$') {
            throw 'Unsupported PWA profile name. Remove the PWA manually and rerun setup.'
        }
        $registrations.Add([pscustomobject]@{ DisplayName=$label; AppId=$app.Groups[1].Value.ToLowerInvariant(); Profile=$profile })
    }
    return $registrations.ToArray()
}
function Assert-BrowserPwaUninstalled {
    param([object[]]$Expected, [string]$Executable)
    foreach ($target in $Expected) {
        Write-Host ("Opening {0} uninstall dialog for {1} (profile: {2})." -f $script:SelectedBrowser.DisplayName,$target.DisplayName,$target.Profile) -ForegroundColor Yellow
        Write-Host 'Leave any Remove browsing/site data option UNCHECKED. Confirm uninstall in the browser.' -ForegroundColor Yellow
        $args = @('--profile-directory="' + $target.Profile + '"', '--uninstall-app-id=' + $target.AppId)
        Start-Process -FilePath $Executable -ArgumentList $args | Out-Null
        $deadline = (Get-Date).AddMinutes(3)
        do {
            Start-Sleep -Seconds 2
            $remaining = @(Get-BrowserTwitterAppRegistrations | Where-Object { $_.AppId -ceq $target.AppId -and $_.Profile -ceq $target.Profile })
            if ($remaining.Count -eq 0) { break }
        } while ((Get-Date) -lt $deadline)
        if ($remaining.Count -ne 0) { throw ('Uninstall was cancelled or timed out for ' + $target.DisplayName + '. Keep site data, uninstall from the browser Apps page, and retry.') }
        Write-Host ('Uninstalled app registration: ' + $target.DisplayName) -ForegroundColor Green
    }
}
function Restore-OwnedPolicyAfterAbort {
    if (Get-PolicyValue) { return }
    if (-not (Test-Path -LiteralPath $script:PolicyStatePath)) { return }
    $saved = Get-Content -LiteralPath $script:PolicyStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $saved.policyValue) { return }
    New-Item -Path $script:PolicyKey -Force | Out-Null
    New-ItemProperty -LiteralPath $script:PolicyKey -Name $script:PolicyName -PropertyType String -Value ([string]$saved.policyValue) -Force | Out-Null
    Write-Warning 'Restored the previous kit-owned policy after the interrupted setup. Restart the selected browser if needed.'
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
function Get-TargetBrowserProcesses {
    # Check only the selected browser's processes. MainWindowHandle is normally
    # zero for Chromium background renderers, GPU, and extension processes.
    return @(Get-Process -Name $script:SelectedBrowser.Process -ErrorAction SilentlyContinue)
}
function Close-BrowserGracefully {
    $processes = @(Get-TargetBrowserProcesses)
    if ($processes.Count -eq 0) { return }
    Write-Host ('Closing ' + $script:SelectedBrowser.DisplayName + ' browser windows...') -ForegroundColor Yellow
    foreach ($proc in $processes) {
        try { if ($proc.MainWindowHandle -ne [IntPtr]::Zero) { [void]$proc.CloseMainWindow() } } catch { }
    }
    $deadline = (Get-Date).AddSeconds(25)
    while (@(Get-TargetBrowserProcesses).Count -gt 0 -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 1
    }
    while (@(Get-TargetBrowserProcesses).Count -gt 0) {
        Write-Host ''
        Write-Warning ($script:SelectedBrowser.DisplayName + ' still has background processes running.')
        Write-Host 'R = Exit the browser using its tray icon or Task Manager, then recheck.'
        Write-Host 'F = FORCE close remaining browser processes. Unsaved drafts/tabs may be lost.'
        Write-Host 'C = Cancel setup (default). Any temporary Twitter policy will be restored.'
        $choice = (Read-Host 'Choose R, F, or C').Trim().ToUpperInvariant()
        switch ($choice) {
            'R' {
                Write-Host 'Waiting up to 30 seconds for the browser to exit...'
                $retry = (Get-Date).AddSeconds(30)
                while (@(Get-TargetBrowserProcesses).Count -gt 0 -and (Get-Date) -lt $retry) {
                    Start-Sleep -Seconds 1
                }
            }
            'F' {
                $confirm = Read-Host 'Type FORCE to confirm closing browser processes (no site data will be deleted)'
                if ($confirm -cne 'FORCE') { throw 'Browser force-close was not authorized. Setup cancelled.' }
                $remaining = @(Get-TargetBrowserProcesses)
                foreach ($proc in $remaining) {
                    try { Stop-Process -Id $proc.Id -Force -ErrorAction Stop }
                    catch { Write-Warning ('Cannot stop browser process ' + $proc.Id + ': ' + $_.Exception.Message) }
                }
                $retry = (Get-Date).AddSeconds(12)
                while (@(Get-TargetBrowserProcesses).Count -gt 0 -and (Get-Date) -lt $retry) {
                    Start-Sleep -Seconds 1
                }
                if (@(Get-TargetBrowserProcesses).Count -gt 0) {
                    throw 'Browser processes are still running after the approved close. Setup cancelled.'
                }
            }
            default { throw 'Browser close cancelled by user. Setup stopped.' }
        }
    }
    Write-Host ($script:SelectedBrowser.DisplayName + ' has exited.') -ForegroundColor Green
}
function Restart-BrowserGracefully([string]$Executable,[string]$Page) {
    Close-BrowserGracefully
    Start-Process -FilePath $Executable -ArgumentList $Page
}
