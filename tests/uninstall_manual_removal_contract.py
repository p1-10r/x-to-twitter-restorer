"""Manual extension-removal steps must be present even if autodetection misses it."""
from pathlib import Path
r = Path(__file__).resolve().parents[1]
main = (r/'scripts/Uninstall-Twitter.ps1').read_text(encoding='utf-8-sig')
helper = (r/'scripts/Twitter.Uninstall.ps1').read_text(encoding='utf-8-sig')
readme = (r/'README.md').read_text(encoding='utf-8')
guide = (r/'UNINSTALL-README.txt').read_text(encoding='utf-8-sig')
for entry in ('brave://extensions','chrome://extensions','edge://extensions'):
    assert entry in readme and entry in guide, entry
for step in ('Twitter Blue Bird Restorer','Remove','Turning the ON/OFF toggle OFF is NOT removal', 'EVERY profile'):
    assert step in helper,step
assert 'Show-TwitterExtensionManualRemovalInstructions -Browsers $browsers' in main
assert 'elseif ($hasArtifacts)' in main
assert 'No kit-managed settings were modified' in main
assert 'Browser removal was not confirmed on disk' in main
assert 'Remove-TwitterRestorerArtifacts -DataRoot $script:DataRoot' in main
assert main.index('Show-TwitterExtensionManualRemovalInstructions -Browsers $browsers') < main.index('Remove-TwitterRestorerArtifacts -DataRoot $script:DataRoot')
assert 'スイッチをOFFにするだけでは不十分' in readme
assert 'ON/OFF スイッチを OFF にするだけでは削除されません' in guide
assert 'Get-TwitterBrowserExtensionRegistrations' in main
print('Manual removal instructions, per-profile confirmation and non-destructive cleanup contract OK')

workflow=(r/'.github/workflows/release.yml').read_text(encoding='utf-8')
assert 'UNINSTALL-README.txt Bootstrap-Twitter.ps1' in workflow
legacy=(r/'Start-Twitter-Remove.cmd').read_text(encoding='utf-8')
assert 'Start-Twitter-Uninstall-All.cmd' in legacy
