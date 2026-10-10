"""Static guardrails only; real Windows/UAC/Brave smoke tests still needed."""
from pathlib import Path
r=Path(__file__).resolve().parents[1]
b=(r/'Bootstrap-Twitter.ps1').read_text(encoding='utf-8')
i=(r/'scripts/Install-Twitter.ps1').read_text(encoding='utf-8-sig')
c=(r/'scripts/Twitter.Common.ps1').read_text(encoding='utf-8')
e=(r/'scripts/Twitter.Elevation.ps1').read_text(encoding='utf-8')
assert 'Invoke-TwitterElevation' in b and 'Invoke-TwitterElevation' in i
assert '-Verb RunAs -Wait -PassThru' in e
assert 'Elevation switched Windows users' in e
assert 'Get-TargetBrowserProcesses' in c
assert 'Stop-Process -Id' in c and "-cne 'FORCE'" in c
assert 'Close-BrowserGracefully }' in i
assert i.index('if (-not $SkipBrowserRestart) { Close-BrowserGracefully }') < i.index('$script:PolicyTemporarilyRemoved = Remove-OwnedPolicyForFreshInstall')
assert 'Remove-Item -LiteralPath $script:DataRoot -Recurse' not in c
assert 'delete-browsing-data' not in c.lower()
print('Admin request, same-user check, confirmed close, preflight ordering OK')
