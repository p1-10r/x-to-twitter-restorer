"""Check presence guards for optional Chromium preferences (PowerShell 5.1 StrictMode)."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
script=(root/'scripts/Twitter.Common.ps1').read_text(encoding='utf-8')
start=script.index('function Get-TwitterExtensionStatus')
end=script.index('function Assert-TwitterExtensionReady', start)
block=script[start:end]
assert 'Get-TwitterOptionalProperty' in script
assert "-Object $prefs -Name 'extensions'" in block
assert "-Object $extensions -Name 'settings'" in block
for missing in ["-Object $item -Name 'manifest'", "-Object $item -Name 'state'", "-Object $itemManifest -Name 'name'"]:
    assert missing in block, missing
assert '$prefs.extensions.settings' not in block
assert '$item.manifest' not in block
assert "$result.Reason = 'No registered extensions" in block
assert 'Get-TwitterOptionalProperty -Object $profileState' in script
assert (root/'tests/extension_status_windows.ps1').exists()
print('PASS optional Chromium extension registration guards')
