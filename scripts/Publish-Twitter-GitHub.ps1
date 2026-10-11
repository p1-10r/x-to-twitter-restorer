# Publishes a new version to GitHub, even when the repo already contains commits.
[CmdletBinding()]
param([string]$Repository = 'p1-10r/x-to-twitter-restorer')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$expectedOwner = 'p1-10r'
$workingDir = Join-Path $env:TEMP ('twitter-publish-' + [guid]::NewGuid().ToString('N'))
function Invoke-Checked {
    param([string]$Program, [string[]]$Arguments)
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program returned exit code $LASTEXITCODE" }
}
function Resolve-Tool {
    param([ValidateSet('git','gh')][string]$ToolName)
    $command = Get-Command -Name ($ToolName + '.exe') -CommandType Application -ErrorAction SilentlyContinue
    if ($command) { return [string]$command.Source }
    $paths = @()
    if ($ToolName -eq 'gh') {
        $paths = @(
            (Join-Path $env:ProgramFiles 'GitHub CLI\gh.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\GitHub CLI\gh.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'GitHub CLI\gh.exe')
        )
    } else {
        $paths = @(
            (Join-Path $env:ProgramFiles 'Git\cmd\git.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'Git\cmd\git.exe')
        )
    }
    foreach ($path in $paths) {
        if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) { return $path }
    }
    return $null
}
function Ensure-Tool {
    param([string]$ToolName, [string]$PackageId, [string]$DisplayName)
    $resolved = Resolve-Tool $ToolName
    if ($resolved) {
        $env:Path = (Split-Path -Parent $resolved) + ';' + $env:Path
        return $resolved
    }
    Write-Host "$DisplayName is missing." -ForegroundColor Yellow
    if ((Read-Host "Type INSTALL to install $DisplayName via Windows Package Manager (winget)") -cne 'INSTALL') {
        throw "$DisplayName is required. Nothing was installed."
    }
    $winget = Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "winget is missing. Install Microsoft App Installer first, or install $DisplayName from the official website."
    }
    & $winget.Source install --id $PackageId --exact --source winget --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) { throw "winget failed installing $DisplayName (exit code $LASTEXITCODE)." }
    # winget can install successfully but does not update this PowerShell process' PATH.
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = @($env:Path, $machinePath, $userPath) -join ';'
    $resolved = Resolve-Tool $ToolName
    if (-not $resolved) { throw "$DisplayName installed, but its executable is not available yet. Close this window, start a fresh one, and rerun Start-Twitter-Publish.cmd." }
    $env:Path = (Split-Path -Parent $resolved) + ';' + $env:Path
    Write-Host "$DisplayName is ready: $resolved" -ForegroundColor Green
    return $resolved
}
try {
    $Repository = $Repository.Trim()
    if ($Repository -match '^[A-Za-z0-9_.-]+$') { $Repository = "$expectedOwner/$Repository" }
    if ($Repository -cnotmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
        throw 'Invalid repository. Use x-to-twitter-restorer or p1-10r/x-to-twitter-restorer.'
    }
    if ($Repository.Split('/')[0] -cne $expectedOwner) { throw "Only $expectedOwner repositories are supported by this kit." }
    $gitExe = Ensure-Tool -ToolName 'git' -PackageId 'Git.Git' -DisplayName 'Git for Windows'
    $ghExe = Ensure-Tool -ToolName 'gh' -PackageId 'GitHub.cli' -DisplayName 'GitHub CLI'
    # OAuth sign-in is user-driven. Never ask users to paste API tokens into this helper.
    Write-Host 'Checking GitHub login...' -ForegroundColor Cyan
    & $ghExe auth status
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'GitHub sign-in is required. A browser window will open for approval.' -ForegroundColor Yellow
        & $ghExe auth login --hostname github.com --git-protocol https --web
        if ($LASTEXITCODE -ne 0) { throw 'GitHub login was not completed.' }
    }
    $login = (& $ghExe api user --jq '.login')
    if ($LASTEXITCODE -ne 0 -or ([string]$login).Trim() -cne $expectedOwner) { throw "GitHub CLI is signed in as '$login'; log in as $expectedOwner before publishing." }
    # Makes git push use gh's authenticated credential helper over HTTPS.
    Invoke-Checked -Program $ghExe -Arguments @('auth','setup-git')
    # Windows PowerShell 5.1 defaults to the system ANSI code page for UTF-8 files
    # without a BOM. Explicit UTF-8 decoding prevents Japanese text from corrupting JSON.
    # Strict decoder also rejects truly invalid UTF-8 instead of replacing bytes silently.
    $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
    $jsonPaths = @(
        (Join-Path $root 'extension\manifest.json'),
        (Join-Path $root 'extension\pwa\twitter.webmanifest'),
        (Join-Path $root 'config.json')
    )
    foreach ($jsonPath in $jsonPaths) {
        try {
            $rawJson = [System.IO.File]::ReadAllText($jsonPath, $utf8)
            $null = ConvertFrom-Json -InputObject $rawJson -ErrorAction Stop
        } catch {
            throw ("Invalid UTF-8 or JSON in {0}: {1}" -f $jsonPath, $_.Exception.Message)
        }
    }
    $manifest = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($jsonPaths[0], $utf8))
    if ([string]$manifest.version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid manifest version.' }
    if ([string]$manifest.name -cne 'Twitter Blue Bird Restorer') { throw 'Unexpected extension manifest.' }
    $tag = 'v' + [string]$manifest.version
    Write-Host "Publishing PUBLIC repository: $Repository" -ForegroundColor Yellow
    Write-Host "Version: $tag"
    if ((Read-Host 'Type PUBLISH to confirm public GitHub upload') -cne 'PUBLISH') {
        Write-Host 'Cancelled.'; return
    }
    $configFile = Join-Path $root 'config.json'
    $config = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($configFile, $utf8))
    $config.github_repo = $Repository
    $config.github_branch = 'main'
    [System.IO.File]::WriteAllText($configFile, ($config | ConvertTo-Json -Depth 6), ([System.Text.UTF8Encoding]::new($false)))

    & $ghExe repo view $Repository --json name | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Repository does not exist: $Repository" }
    # Clone the current remote to avoid non-fast-forward pushes and unrelated histories.
    Invoke-Checked -Program $ghExe -Arguments @('repo','clone',$Repository,$workingDir)
    $currentBranch = & $gitExe -C $workingDir branch --show-current
    if ($LASTEXITCODE -ne 0) { throw 'Could not determine the cloned repository branch.' }
    if ([string]$currentBranch -cne 'main') { Invoke-Checked -Program $gitExe -Arguments @('-C',$workingDir,'checkout','main') }
    $existingTag = @(& $gitExe -C $workingDir tag --list $tag)
    if ($existingTag.Count -ne 0) {
        throw "Tag $tag already exists. Bump extension/manifest.json version before publishing a new release."
    }
    $paths = @('extension','resources','scripts','.github','tests','config.json','README.md','Bootstrap-Twitter.ps1','.gitignore')
    $paths += @(Get-ChildItem -LiteralPath $root -Filter '*.cmd' -File | ForEach-Object { $_.Name })
    foreach ($path in $paths) {
        $source = Join-Path $root $path
        $destination = Join-Path $workingDir $path
        if (Test-Path -LiteralPath $source -PathType Container) {
            New-Item -ItemType Directory -Path $destination -Force | Out-Null
            Get-ChildItem -LiteralPath $source -Force | ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination $destination -Recurse -Force
            }
        } else {
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
    }
    Invoke-Checked -Program $gitExe -Arguments @('-C',$workingDir,'add','extension','resources','scripts','.github','tests','config.json','README.md','Bootstrap-Twitter.ps1','.gitignore','*.cmd')
    & $gitExe -C $workingDir diff --cached --quiet
    if ($LASTEXITCODE -eq 0) { throw 'No changes to publish. Bump the extension version to release a new update.' }
    if ($LASTEXITCODE -ne 1) { throw 'Failed to examine staged Git changes.' }
    $gitName = & $gitExe -C $workingDir config user.name
    if (-not $gitName) { Invoke-Checked -Program $gitExe -Arguments @('-C',$workingDir,'config','user.name',$expectedOwner) }
    $gitEmail = & $gitExe -C $workingDir config user.email
    if (-not $gitEmail) { Invoke-Checked -Program $gitExe -Arguments @('-C',$workingDir,'config','user.email','204170641+p1-10r@users.noreply.github.com') }
    Invoke-Checked -Program $gitExe -Arguments @('-C',$workingDir,'commit','-m',"Release $tag")
    Invoke-Checked -Program $gitExe -Arguments @('-C',$workingDir,'push','origin','main')
    Invoke-Checked -Program $gitExe -Arguments @('-C',$workingDir,'tag',$tag)
    Invoke-Checked -Program $gitExe -Arguments @('-C',$workingDir,'push','origin',$tag)
    Write-Host ('Source uploaded: https://github.com/' + $Repository) -ForegroundColor Green
    Write-Host ('GitHub Actions release: https://github.com/' + $Repository + '/actions')
} catch {
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    if (Test-Path -LiteralPath $workingDir) { Remove-Item -LiteralPath $workingDir -Recurse -Force -ErrorAction SilentlyContinue }
}
