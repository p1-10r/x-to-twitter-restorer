(function () {
  "use strict";

  const { replaceUiLabel, replacePageTitle, isXBrandLogoPath } = globalThis.TwitterBrandRules;
  const birdUrl = chrome.runtime.getURL("assets/twitter-bird.svg");
  const faviconDataUrl = globalThis.TwitterBirdFavicon;

  // データ部分には、メニューやヘッダーの内側であっても触れない。
  const PROTECTED_SELECTOR = [
    "article", "[role='article']", "[data-testid='tweet']", "[data-testid='tweetText']",
    "[data-testid='UserName']", "[data-testid='UserDescription']",
    "[data-testid='UserCell']", "[data-testid='cellInnerDiv']",
    "[data-testid='SideNav_AccountSwitcher_Button']",
    "[data-testid='trend']", "[data-testid='typeaheadResult']",
    "[data-testid='searchBox']", "[data-testid='card.wrapper']",
    "[data-testid='DMDrawer']", "blockquote", "[contenteditable]",
    "[role='textbox']", "input", "textarea", "select", "option"
  ].join(", ");

  // Xが独自に用意したUIのうち、ユーザーの文章が入らない箇所に絞る。
  const UI_CHROME_SELECTOR = [
    "header[role='banner']", "nav[role='navigation']", "[role='menu']",
    "[role='menubar']", "footer"
  ].join(", ");
  const OFFICIAL_BRAND_LINK_SELECTOR = [
    "a[href^='https://about.x.com/']",
    "a[href^='https://help.x.com/']",
    "a[href^='https://business.x.com/']",
    "a[href='/settings/about']",
    "a[href='/i/premium_sign_up']"
  ].join(", ");

  const pendingRoots = new Set();
  let scheduled = false;

  function isProtected(element) {
    return Boolean(element && (element.isContentEditable || element.closest(PROTECTED_SELECTOR)));
  }

  function isSignedOutLanding() {
    return ["/", "/i/flow/login", "/i/flow/signup"].includes(location.pathname) &&
      !document.querySelector("[data-testid='primaryColumn']");
  }

  function isAllowedUI(element) {
    if (!element || isProtected(element)) return false;
    if (element.closest(UI_CHROME_SELECTOR)) return true;
    if (element.closest(OFFICIAL_BRAND_LINK_SELECTOR)) return true;
    // ログアウト時のトップページやログイン画面にある固定の案内文。
    return isSignedOutLanding() && Boolean(element.closest("main, [role='main']"));
  }

  function updateTextNode(node) {
    const parent = node.parentElement;
    if (!isAllowedUI(parent)) return;
    const result = replaceUiLabel(node.nodeValue);
    if (result !== node.nodeValue) node.nodeValue = result;
  }

  function updateAttributes(element) {
    if (!isAllowedUI(element)) return;
    for (const name of ["aria-label", "title"]) {
      if (!element.hasAttribute(name)) continue;
      const value = element.getAttribute(name);
      const replacement = replaceUiLabel(value);
      if (value !== replacement) element.setAttribute(name, replacement);
    }
  }

  // Xのナビゲーションにあるブランドリンク。家のホームアイコンと区別する。
  function isBrandHomeLink(link) {
    if (!link || link.getAttribute("href") !== "/home") return false;
    const label = link.getAttribute("aria-label");
    return label === "X" || label === "𝕏" || label === "Twitter" ||
      Boolean(link.closest("h1, [role='heading']")) ||
      Boolean(link.querySelector("h1, [role='heading']"));
  }

  function updateLogo(svg) {
    if (isProtected(svg)) return;
    const inChrome = Boolean(svg.closest(UI_CHROME_SELECTOR));
    const inLanding = isSignedOutLanding() && Boolean(svg.closest("main, [role='main']"));
    if (!inChrome && !inLanding) return;

    const link = svg.closest("a[href='/home']");
    const inBrandLink = inChrome && isBrandHomeLink(link);
    // SVGパスからの判定と、X公式ホームブランドリンクの二段構え。
    const isBrand = inBrandLink || Array.from(svg.querySelectorAll("path[d]"))
      .some(path => isXBrandLogoPath(path.getAttribute("d")));
    if (isBrand) {
      svg.setAttribute("data-twitter-restored-logo", "true");
      if (inBrandLink) link.setAttribute("data-twitter-restored-link", "true");
    } else {
      svg.removeAttribute("data-twitter-restored-logo");
      if (link && link.hasAttribute("data-twitter-restored-link") &&
          !link.querySelector("svg[data-twitter-restored-logo='true']")) {
        link.removeAttribute("data-twitter-restored-link");
      }
    }
  }

  function updateFavicon() {
    if (!document.head || !faviconDataUrl) return;
    // 既存のiconをすべて書き換えて、X側が新しいiconを足しても追従する。
    const icons = Array.from(document.head.querySelectorAll("link[rel~='icon']"));
    for (const icon of icons) {
      if (icon.getAttribute("href") !== faviconDataUrl) icon.setAttribute("href", faviconDataUrl);
      if (icon.type !== "image/png") icon.type = "image/png";
      if (icon.hasAttribute("sizes")) icon.removeAttribute("sizes");
    }
    // Chromium/Braveは最後のiconを採用するケースがあるため専用linkも置く。
    let own = document.getElementById("twitter-blue-bird-favicon");
    if (!own) {
      own = document.createElement("link");
      own.id = "twitter-blue-bird-favicon";
      own.rel = "icon";
      own.type = "image/png";
      own.href = faviconDataUrl;
      document.head.appendChild(own);
    }
    // 他のfaviconが追加されたときにだけ優先順位を戻す（毎回移動しない）。
    if (icons.some(icon => icon !== own && Boolean(own.compareDocumentPosition(icon) & Node.DOCUMENT_POSITION_FOLLOWING))) {
      document.head.appendChild(own);
    }
  }

  function updateTabTitle() {
    const current = document.title;
    const next = replacePageTitle(current, location.pathname);
    if (next !== current) document.title = next;

    // Chromium PWA window captions include the *installed app name* separately.
    // application-title controls only the page-specific portion after that name;
    // it cannot rename an already installed X app.
    if (!document.head) return;
    let own = document.head.querySelector('meta[name="application-title"]');
    if (!own) {
      own = document.createElement("meta");
      own.setAttribute("name", "application-title");
      document.head.appendChild(own);
    }
    // Avoid "Twitter - Twitter - ホーム / Twitter" after the native PWA
    // is registered as Twitter. This only updates metadata, never posts.
    const pwaSubtitle = next.replace(/^Twitter - /, "");
    if (own.content !== pwaSubtitle) own.content = pwaSubtitle;
  }

  function scan(root) {
    if (root.nodeType === Node.TEXT_NODE) {
      updateTextNode(root);
      return;
    }
    if (root.nodeType !== Node.ELEMENT_NODE && root.nodeType !== Node.DOCUMENT_NODE) return;
    if (root.nodeType === Node.ELEMENT_NODE && isProtected(root)) return;

    if (root.nodeType === Node.ELEMENT_NODE) {
      updateAttributes(root);
      if (root.matches("svg")) updateLogo(root);
    }

    for (const element of root.querySelectorAll("[aria-label], [title]")) {
      updateAttributes(element);
    }
    for (const svg of root.querySelectorAll("svg")) {
      updateLogo(svg);
    }

    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      updateTextNode(node);
    }
  }

  function flush() {
    scheduled = false;
    const roots = Array.from(pendingRoots);
    pendingRoots.clear();
    for (const root of roots) {
      if (root.isConnected || root === document) scan(root);
    }
    updateFavicon();
    updateTabTitle();
  }

  function queue(root) {
    if (!root) return;
    pendingRoots.add(root);
    if (!scheduled) {
      scheduled = true;
      requestAnimationFrame(flush);
    }
  }

  function start() {
    const observer = new MutationObserver(mutations => {
      let faviconChanged = false;
      for (const mutation of mutations) {
        if (mutation.type === "childList") {
          for (const added of mutation.addedNodes) queue(added);
          // Reactがpathだけを差し替えた場合も親SVGのロゴ判定を再実行。
          if (mutation.target.nodeType === Node.ELEMENT_NODE) {
            const svg = mutation.target.closest("svg");
            if (svg) queue(svg);
          }
          if (mutation.target === document.head) faviconChanged = true;
        } else if (mutation.type === "characterData") {
          queue(mutation.target);
        } else if (mutation.type === "attributes") {
          if (mutation.target.matches("link[rel~='icon']")) {
            faviconChanged = true;
          } else {
            const svg = mutation.target.closest("svg");
            queue(svg || mutation.target);
          }
        }
      }
      if (faviconChanged) queue(document.head);
    });
    observer.observe(document.documentElement, {
      subtree: true,
      childList: true,
      characterData: true,
      attributes: true,
      attributeFilter: ["aria-label", "title", "d", "href", "rel", "content"]
    });
    queue(document.documentElement);
  }

  if (document.documentElement) start();
  else document.addEventListener("DOMContentLoaded", start, { once: true });
})();
