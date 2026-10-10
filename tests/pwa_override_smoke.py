"""Tests the manifest injection and post preservation, but not native PWA installation.

The test uses about:blank with script injection because this sandbox blocks page navigation.
"""
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1] / "extension"
HTML = '''<!doctype html><html><head>
<title>X - ホーム / X</title><link rel="manifest" href="/old.webmanifest">
</head><body><main><article id="post">The variable X is important</article></main></body></html>'''

with sync_playwright() as p:
    browser = p.chromium.launch(executable_path='/usr/bin/chromium',headless=True)
    try:
        page=browser.new_page()
        errors=[]
        page.on('pageerror',lambda e: errors.append(str(e)))
        page.goto('about:blank')
        page.set_content(HTML)
        page.evaluate('window.chrome = {runtime:{getURL: (path) => "chrome-extension://test/" + path}}')
        source=(ROOT/'pwa-manifest.js').read_text(encoding='utf-8')
        # The synthetic page has an about:blank origin, so skip the x.com-only guard for this test.
        source=source.replace('if (location.hostname !== "x.com" && location.hostname !== "www.x.com") return;', 'if (false) return;')
        page.add_script_tag(content=source)
        page.wait_for_function('document.querySelector("link#twitter-blue-bird-app-manifest")?.href === "chrome-extension://test/pwa/twitter.webmanifest"')
        assert page.locator('head link[rel=manifest]').first.get_attribute('id') == 'twitter-blue-bird-app-manifest'
        assert page.locator('meta[name="application-name"]').get_attribute('content') == 'Twitter'
        assert page.locator('#post').inner_text() == 'The variable X is important'
        page.evaluate('document.head.insertAdjacentHTML("afterbegin", "<link rel=manifest href=/later.webmanifest>")')
        page.wait_for_function('document.head.firstElementChild?.id === "twitter-blue-bird-app-manifest"')
        assert page.locator('head link[rel=manifest]').count() == 3
        assert not errors, errors
        print('PASS: PWA manifest precedence, app name, dynamic manifest additions, post protection')
    finally:
        browser.close()
