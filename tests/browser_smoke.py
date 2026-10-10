"""DOM integration smoke test. Requires Python Playwright and Chromium.

The test runner has no permission to navigate websites, so the scripts are run on a
local synthetic page in Chromium. This tests runtime DOM behavior, not X's live UI.
"""
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1] / "extension"
HTML = '''<!doctype html><html><head><title>X - ホーム / X</title>
<link rel="icon" href="/favicon.ico"></head><body>
<header role="banner"><nav role="navigation">
 <h1><a aria-label="X" href="/home"><svg viewBox="0 0 24 24" width="40" height="40">
 <path d="M18.901 1.153h3.68l-8.04 9.19 9.46 12.5"></path></svg></a></h1>
 <span id="nav-brand">About X</span>
</nav><button data-testid="SideNav_AccountSwitcher_Button"><span id="account">X</span></button></header>
<main><div data-testid="primaryColumn"><h1 id="main-heading">X</h1>
<article data-testid="tweet"><div data-testid="tweetText" id="tweet">X</div></article>
</div><input id="input" value="X"><textarea id="composer">X</textarea></main>
<footer><span id="footer">Xについて</span></footer>
</body></html>'''

with sync_playwright() as p:
    browser = p.chromium.launch(executable_path="/usr/bin/chromium", headless=True,
                                args=["--no-sandbox", "--disable-dev-shm-usage"])
    try:
        page = browser.new_page()
        errors = []
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.goto("about:blank")
        page.set_content(HTML)
        page.evaluate('window.chrome = {runtime: {getURL: p => "chrome-extension://test/" + p}}')
        page.add_style_tag(path=str(ROOT / "content.css"))
        page.add_script_tag(path=str(ROOT / "brand-rules.js"))
        page.add_script_tag(path=str(ROOT / "favicon-data.js"))
        page.add_script_tag(path=str(ROOT / "content.js"))
        page.wait_for_function('''() => document.querySelector('#nav-brand').textContent === 'About Twitter' &&
            document.title === 'X - ホーム / Twitter' && document.querySelector('svg').dataset.twitterRestoredLogo === 'true' ''', timeout=15000)
        assert page.locator('#tweet').inner_text() == 'X'
        assert page.locator('#account').inner_text() == 'X'
        assert page.locator('#main-heading').inner_text() == 'X'
        assert page.locator('#input').input_value() == 'X'
        assert page.locator('#composer').input_value() == 'X'
        assert page.locator('#footer').inner_text() == 'Twitterについて'
        assert page.locator('a[href="/home"]').get_attribute('aria-label') == 'Twitter'
        style = page.locator('svg').evaluate('(e) => getComputedStyle(e).backgroundImage')
        assert 'twitter-bird.svg' in style, style
        assert all(v.startswith('data:image/png;base64,') for v in page.locator('link[rel="icon"]').evaluate_all('(els) => els.map(e => e.href)'))
        assert page.locator('a[href="/home"]').get_attribute('data-twitter-restored-link') == 'true'
        assert page.locator('link#twitter-blue-bird-favicon').count() == 1
        assert page.locator('meta[name=application-title]').get_attribute('content') == 'X - ホーム / Twitter'
        page.locator('nav').evaluate('e => e.insertAdjacentHTML("beforeend", "<span id=dynamic>X Premium</span>")')
        page.wait_for_function('document.querySelector("#dynamic")?.textContent === "Twitter Premium"')
        page.locator('#nav-brand').evaluate('e => e.textContent = "X"')
        page.wait_for_function('document.querySelector("#nav-brand").textContent === "Twitter"')
        page.evaluate('document.title = "Explore / X"')
        page.wait_for_function('document.title === "Explore / Twitter"')
        page.wait_for_function('document.querySelector("meta[name=application-title]")?.content === "Explore / Twitter"')
        assert errors == [], errors
        print('PASS: logo, favicon, tab title, UI, dynamic updates, post/profile/input protection')
    finally:
        browser.close()
