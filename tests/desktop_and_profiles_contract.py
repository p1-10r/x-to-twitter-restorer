from pathlib import Path
from PIL import Image
root=Path(__file__).resolve().parents[1]
common=(root/'scripts/Twitter.Common.ps1').read_text()
installer=(root/'scripts/Install-Twitter.ps1').read_text(encoding='utf-8-sig')
repair=(root/'scripts/Repair-Twitter-Desktop.ps1').read_text(encoding='utf-8-sig')
assert common.index('function Get-TwitterProfileCandidates') < common.index('function Get-TwitterExtensionStatus')
assert 'Get-TwitterEnabledProfiles' in installer
assert installer.index('Get-TwitterEnabledProfiles') < installer.index('Assert-TwitterExtensionReady')
assert installer.index('Repair-TwitterDesktopIcons') > installer.index('Set-TwitterPolicy')
assert 'function Repair-TwitterDesktopIcons' in common
assert "-notmatch $script:SelectedBrowser.AppPathMatch" in common
assert "--app-id" in common
assert "IconLocation = $icon + ',0'" in common
assert 'Set-TwitterPolicy' not in repair
assert 'Remove-OwnedPolicyForFreshInstall' not in repair
assert "Start-Twitter-Desktop-Icon-Fix.cmd" in (root/'README.md').read_text()
icon=Image.open(root/'resources/twitter-large.ico').convert('RGBA')
assert icon.getpixel((0,0))[3] == 0
print('PASS repair targets only browser PWA links and keeps transparent ICO')
