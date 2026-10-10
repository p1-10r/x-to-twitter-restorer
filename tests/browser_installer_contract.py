"""Source level safeguards for the Windows multi-browser installer.
This does not replace a real Windows PowerShell and browser integration test.
"""
from pathlib import Path
import re
r = Path(__file__).resolve().parents[1]
common = (r/'scripts/Twitter.Common.ps1').read_text(encoding='utf-8')
installer = (r/'scripts/Install-Twitter.ps1').read_text(encoding='utf-8-sig')
bootstrap = (r/'Bootstrap-Twitter.ps1').read_text(encoding='utf-8')
fix = (r/'scripts/Fix-Twitter-Taskbar.ps1').read_text(encoding='utf-8')
remove = (r/'scripts/Remove-Twitter.ps1').read_text(encoding='utf-8')
for id, policy in [('brave', r'BraveSoftware\Brave'), ('chrome', r'Google\Chrome'), ('edge', r'Microsoft\Edge')]:
    assert f"'{id}' {{" in common
    assert policy in common, (id,policy)
    assert f"'installed-policy-' + $Browser.Id" in common
assert 'UserChoiceLatest' in common and 'UserChoice' in common
assert common.index("'UserChoiceLatest'") < common.index("'UserChoice'")
assert 'Read-Host \'Browser number (Enter cancels)\'' in common
assert "Select-TwitterBrowser -Requested $Browser" in installer
assert 'Initialize-TwitterBrowser $selected' in installer
assert 'Get-BrowserTwitterAppRegistrations' in installer
assert 'Assert-BrowserPwaUninstalled' in installer
assert 'Restart-BrowserGracefully -Executable $browserExe' in installer
assert "-Browser $selected.Id" in installer
assert 'AppPathMatch' in fix
assert 'Select-TwitterBrowser -Requested $Browser' in fix
assert 'Select-TwitterBrowser -Requested $Browser' in remove
assert '-FreshPwa -Browser $Browser' in bootstrap
consent = installer.index("Read-Host '上記内容に同意して実行する場合は REINSTALL")
for mutation in ['Remove-OwnedPolicyForFreshInstall', 'Sync-TwitterExtension', 'Set-TwitterPolicy', 'Restart-BrowserGracefully -Executable']:
    assert consent < installer.index(mutation), mutation
assert "if ($uninstall -match '(?i)--user-data-dir=')" in common
assert 'delete-browsing-data' not in (common + installer).lower()
assert 'profile' in common.lower() and 'サイトデータ' in installer
assert 'installed-policy.json' in common # legacy Brave state
print('PASS multi-browser mapping, selection, consent, scoped uninstall, legacy state')
