import json
import re
from pathlib import Path
root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / 'extension/manifest.json').read_text(encoding='utf-8'))
assert manifest['version'] == '1.5.11'
assert manifest['manifest_version'] == 3
assert 'https://x.com/*' in manifest['content_scripts'][0]['matches']
for js in manifest['content_scripts'][0]['js']:
    assert (root / 'extension' / js).is_file()
for icon in manifest['icons'].values():
    assert (root / 'extension' / icon).is_file()
for script in ('Install-Twitter.ps1','Update-Twitter.ps1','Remove-Twitter.ps1','Twitter.Common.ps1','Fix-Twitter-Taskbar.ps1','Repair-Twitter-Desktop.ps1','Diagnose-Twitter.ps1'):
    assert (root / 'scripts' / script).is_file()
fix = (root / 'scripts/Fix-Twitter-Taskbar.ps1').read_text(encoding='utf-8')
assert '$matches +=' not in fix.lower()
assert '$twitterShortcuts.Add($file)' in fix
for cmd in root.glob('Start-*.cmd'):
    text = cmd.read_text(encoding='utf-8')
    for path in re.findall(r'%~dp0scripts\\([^"\s]+\.ps1)', text):
        assert (root / 'scripts' / path).exists(), (cmd.name, path)
assert (root / '.github/workflows/release.yml').is_file()
print('Package layout, paths, extension manifest and $Matches fix OK')

# Regression: PowerShell 5.1's default ANSI Get-Content mangles Japanese manifest text.
publish = (root / 'scripts/Publish-Twitter-GitHub.ps1').read_text(encoding='utf-8')
assert 'System.Text.UTF8Encoding]::new($false, $true)' in publish
assert '[System.IO.File]::ReadAllText($jsonPath, $utf8)' in publish
assert 'ConvertFrom-Json -InputObject $rawJson -ErrorAction Stop' in publish
assert 'Get-Content -LiteralPath (Join-Path $root' not in publish
assert 'Invoke-Checked $ghExe @(' not in publish
assert 'Invoke-Checked $gitExe @(' not in publish
for rel in ('extension/manifest.json', 'extension/pwa/twitter.webmanifest', 'config.json'):
    json.loads((root / rel).read_text(encoding='utf-8'))
print('PowerShell UTF-8 publishing and JSON validation regression checks OK')
