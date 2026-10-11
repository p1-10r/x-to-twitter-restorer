"""Check presence guards for optional Chromium preferences (PowerShell 5.1 StrictMode)."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
script=(root/'scripts/Twitter.Common.ps1').read_text(encoding='utf-8')
start=script.index('function Get-TwitterExtensionStatus')
end=script.index('function Assert-TwitterExtensionReady', start)
block=script[start:end]
assert 'Get-TwitterOptionalProperty' in script
assert "-Object $prefs -Name 'extensions'" in block
assert "-Name 'settings'" in block
for missing in ["-Object $item -Name 'manifest'", "-Object $item -Name 'state'", "-Object $itemManifest -Name 'name'"]:
    assert missing in block, missing
assert '$prefs.extensions.settings' not in block
assert '$item.manifest' not in block
assert "'Secure Preferences','Preferences'" in block
assert 'No extensions.settings found in Preferences or Secure Preferences' in block
assert 'Get-Content -LiteralPath $preferences -Raw -Encoding UTF8' in block
assert 'Get-TwitterOptionalProperty -Object $profileState' in script
assert (root/'tests/extension_status_windows.ps1').exists()
print('PASS optional Chromium extension registration guards')

assert "Read-Host 'Copy the extension ID" in script
assert 'User visually confirmed enabled extension ID:' in script
assert "Read-Host 'Type ENABLED" in script

# A PowerShell 5.1 if-expression collapses an array with one record to a scalar.
# Keep the counted records in a real List[object] even when exactly one exists.
status_test=(root/'tests/extension_status_windows.ps1').read_text(encoding='utf-8-sig')
assert "$records = New-Object 'System.Collections.Generic.List[object]'" in block
assert '$result.RecordsSeen += $records.Count' in block
assert '$records = if (' not in block
assert "'One registered extension does not scalar-unroll' 1" in status_test
assert "'Multiple registered extensions retain exact count' 3" in status_test
assert "'Empty settings' 0" in status_test
print('PASS regression guard: strict-mode safe record counting (0, 1, many)')
