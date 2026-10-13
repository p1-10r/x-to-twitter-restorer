from pathlib import Path
root=Path(__file__).resolve().parents[1]
common=(root/'scripts/Twitter.Common.ps1').read_text(encoding='utf-8-sig')
installer=(root/'scripts/Install-Twitter.ps1').read_text(encoding='utf-8-sig')
assert 'create_desktop_shortcut=$false' in common
assert 'create_desktop_shortcut=$true' not in common
assert 'ConvertTo-TwitterSingleShortcutPolicy' in common
assert 'Disable-OwnedTwitterPolicyDesktopShortcut' in common
assert '[IO.File]::Replace($temporary, $destination, $backup)' in common
assert '[IO.File]::Replace($temporary, $script:PolicyStatePath, $null)' not in common
assert 'Policy state readback mismatch.' in common
assert 'Get-TwitterDuplicateDesktopShortcuts' in common
assert 'Backup-TwitterDuplicateDesktopShortcuts' in installer
assert 'Backup-TwitterDuplicateDesktopShortcuts' in common
assert "'Twitter.lnk'" in common
assert 'StringComparison]::OrdinalIgnoreCase' in common
assert 'Move-Item -LiteralPath $duplicate.FullName' in common
assert 'Remove-Item -LiteralPath $duplicate.FullName' not in common
assert (root/'Start-Twitter-Stop-Duplicates.cmd').exists()
assert (root/'scripts/Stop-Twitter-Desktop-Duplicates.ps1').exists()
assert 'Disable-OwnedTwitterPolicyDesktopShortcut' in (root/'scripts/Stop-Twitter-Desktop-Duplicates.ps1').read_text(encoding='utf-8-sig')
print('PASS: managed desktop shortcut duplicate prevention contract')

# Windows FindFirstFile / provider -Filter may match filename.* with filename.
# Compare exact file names using a suffix regex, with a canary to ensure
# real *.tmp/*.bak leftovers still fail the Windows integration test.
win_test=(root/'tests/desktop_duplication_windows.ps1').read_text(encoding='utf-8-sig')
assert "-Filter 'installed-policy.json.*'" not in win_test
assert r"-match '^installed-policy\.json\..+$'" in win_test
assert 'installed-policy.json.test-probe.tmp' in win_test
assert 'Temporary migration or backup files were left behind:' in win_test
