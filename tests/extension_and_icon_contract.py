"""Guard source preflight ordering and imported transparency; Windows execution remains untested."""
from pathlib import Path
import json, hashlib
from PIL import Image
root=Path(__file__).resolve().parents[1]
script=(root/'scripts/Install-Twitter.ps1').read_text(encoding='utf-8-sig')
common=(root/'scripts/Twitter.Common.ps1').read_text(encoding='utf-8')
manifest=json.loads((root/'extension/manifest.json').read_text(encoding='utf-8'))
assert manifest['version']=='1.5.15'
assert script.index('Assert-TwitterExtensionReady -Executable') < script.index('Remove-OwnedPolicyForFreshInstall')
assert script.index('Assert-TwitterExtensionReady -Executable') < script.index('Set-TwitterPolicy')
for t in ['function Get-TwitterExtensionStatus','function Assert-TwitterExtensionReady','Preferences','Load unpacked','Get-TwitterTargetProfile','Saved state=0','Extension registration was not detected']:
    assert t in common, t
assert 'Sync-TwitterExtension' in script and 'Get-TwitterEnabledProfiles' in script
assert script.index('Assert-TwitterPublishedIconReady') < script.index('Remove-OwnedPolicyForFreshInstall')
assert '-Style Big-Blue-Bird' in script
assert (root/'resources/twitter-large.ico').read_bytes() == (root/'scripts/icons/Twitter-Big-Blue-Bird.ico').read_bytes()
for loc in ['resources/twitter-pwa.png','extension/assets/icon-128.png','extension/assets/icon-192.png','extension/assets/icon-512.png']:
    im=Image.open(root/loc).convert('RGBA')
    assert im.getchannel('A').getextrema() == (0,255),loc
    assert im.getpixel((0,0))[3] == 0,loc
assert 'Get-TwitterEnabledProfiles' in common
assert 'Get-TwitterDesktopLinks' in common
assert 'Repair-TwitterDesktopIcons' in common
assert (root/'Start-Twitter-Desktop-Icon-Fix.cmd').exists()
assert (root/'scripts/Repair-Twitter-Desktop.ps1').exists()
print('Extension profile lookup, desktop repair and transparency checks OK')
