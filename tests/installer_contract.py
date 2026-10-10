"""Regression checks for consent and non-destructive PWA replacement flow.
These are source-contract checks, NOT a Windows/Brave integration test.
"""
from pathlib import Path
r=Path(__file__).resolve().parents[1]
i=(r/'scripts/Install-Twitter.ps1').read_text(encoding='utf-8-sig')
c=(r/'scripts/Twitter.Common.ps1').read_text(encoding='utf-8')
b=(r/'Bootstrap-Twitter.ps1').read_text(encoding='utf-8')
cmd=(r/'Start-Twitter-Bootstrap.cmd').read_text(encoding='utf-8')
assert i.index("Read-Host '上記内容に同意して実行する場合は REINSTALL") < i.index('Remove-OwnedPolicyForFreshInstall')
assert i.index("Read-Host '上記内容に同意して実行する場合は REINSTALL") < i.index('Sync-TwitterExtension')
assert i.index("Read-Host '上記内容に同意して実行する場合は REINSTALL") < i.index('Set-TwitterPolicy')
for key in ['WebAppInstallForceList','ブラウザを終了','サイトデータ','プロフィール','更新タスク']:
    assert key in i, key
assert 'Get-BrowserTwitterAppRegistrations' in i and 'Assert-BrowserPwaUninstalled' in i
assert 'Restored the previous kit-owned policy' in c
assert '--uninstall-app-id=' in c and 'Start-Process -FilePath $Executable' in c
assert 'Remove-Item -LiteralPath $script:DataRoot -Recurse' not in c
assert 'delete-browsing-data' not in (i+c).lower()
assert 'Read-Host' in b and 'if (-not $NoPause' in b
assert '-NoPause' in cmd and 'pause' in cmd
assert "throw 'Twitter setup failed." in i
print('Consent-before-mutation, browser-specific native PWA removal, bootstrap pause contract OK')
