"""Contract tests for Windows-specific fixes; Windows integration runs in Actions."""
from pathlib import Path
from PIL import Image
root = Path(__file__).resolve().parents[1]
common = (root / 'scripts/Twitter.Common.ps1').read_text(encoding='utf-8-sig')
repair = (root / 'scripts/Repair-Twitter-Desktop.ps1').read_text(encoding='utf-8-sig')
status_test = (root / 'tests/extension_status_windows.ps1').read_text(encoding='utf-8-sig')
assert "Get-TwitterOptionalProperty -Object $item -Name 'path'" in common
assert "Get-TwitterOptionalProperty -Object $item -Name 'state'" in common
assert 'if ($samePath -and (Test-Path -LiteralPath $localManifest' in common
assert 'if ($cachedVersion -and $requiredVersion -and' in common
assert "Localized browser cached name with matching stable extension path" in status_test
assert "Manifest cached as JSON string" in status_test
assert "Matching name but old unpacked folder cannot auto-update" in status_test
assert 'SHChangeNotify' in common
assert 'Notify-TwitterShellIconChanged -Paths $changedPaths.ToArray()' in common
assert 'twitter-bird-v1.5.10.ico' in common
assert 'Set-TwitterPolicy' not in repair
assert (root/'Start-Twitter-Diagnostics.cmd').exists()
assert (root/'scripts/Diagnose-Twitter.ps1').exists()
ico = Image.open(root/'resources/twitter-large.ico')
assert {(16,16),(24,24),(32,32),(48,48),(256,256)}.issubset(ico.info['sizes'])
image = ico.convert('RGBA')
assert image.getpixel((0, 0))[3] == 0
print('PASS stable source registration, cache-busting icon, read-only diagnostics')
