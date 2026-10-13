"""Static guards for the verified cross-version installer mixup.

PowerShell execution needs a Windows machine; these checks ensure the exact
staging/validation path is present in the published kit.
"""
from pathlib import Path
import json
root=Path(__file__).resolve().parents[1]
boot=(root/'Bootstrap-Twitter.ps1').read_text(encoding='utf-8')
common=(root/'scripts/Twitter.Common.ps1').read_text(encoding='utf-8')
version=json.loads((root/'extension/manifest.json').read_text(encoding='utf-8'))['version']
assert version=='1.5.18'
assert 'if ($localVersion -gt $releaseVersion)' in boot
assert 'if ([string]$latest.tag_name -cne' in boot
assert 'Get-ChildItem -LiteralPath $expand -Force' in boot
assert 'Copy-Item -LiteralPath $_.FullName -Destination $releaseDir' in boot
assert "& (Join-Path $releaseDir 'scripts\\Install-Twitter.ps1')" in boot
assert "& (Join-Path $cache 'scripts\\Install-Twitter.ps1')" not in boot
assert 'if ([version]$previousVersion -gt [version]$newVersion)' in common
assert 'Staged installer version mismatch' in boot
print('PASS: release version guard, stable extension downgrade guard, isolated installation')
