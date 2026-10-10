/**
 * PWA install metadata override. Only <head> and application metadata are touched.
 * Post content, user names, composer text, and site APIs are left alone.
 */
(function () {
  "use strict";
  if (location.hostname !== "x.com" && location.hostname !== "www.x.com") return;

  const ID = "twitter-blue-bird-app-manifest";
  const manifestUrl = chrome.runtime.getURL("pwa/twitter.webmanifest");
  let queued = false;
  let overrideUnavailable = false;

  function disableOverride() {
    // If the browser refuses an extension-hosted manifest (e.g. site CSP),
    // leave the original site manifest installable.
    overrideUnavailable = true;
    document.getElementById(ID)?.remove();
    observer.disconnect();
  }

  function ensureInstallMetadata() {
    queued = false;
    const head = document.head;
    if (!head || overrideUnavailable) return;

    let own = document.getElementById(ID);
    if (!own || own.parentElement !== head) {
      own = document.createElement("link");
      own.id = ID;
      own.rel = "manifest";
      own.crossOrigin = "anonymous";
      own.href = manifestUrl;
      own.addEventListener("error", disableOverride, { once: true });
      head.insertBefore(own, head.firstChild);
    } else {
      if (own.getAttribute("href") !== manifestUrl) own.setAttribute("href", manifestUrl);
      if (own.rel !== "manifest") own.rel = "manifest";
      if (own.crossOrigin !== "anonymous") own.crossOrigin = "anonymous";
    }

    // Chromium follows the first rel=manifest link when multiple exist.
    // Leave the site's original links alone; move ours to first when needed.
    if (head.firstElementChild !== own) head.insertBefore(own, head.firstChild);

    let appName = head.querySelector('meta[name="application-name"]');
    if (!appName) {
      appName = document.createElement("meta");
      appName.setAttribute("name", "application-name");
      head.appendChild(appName);
    }
    if (appName.content !== "Twitter") appName.content = "Twitter";
  }

  function queue() {
    if (overrideUnavailable || queued) return;
    queued = true;
    queueMicrotask(ensureInstallMetadata);
  }

  const observer = new MutationObserver(mutations => {
    for (const item of mutations) {
      if (item.type === "childList") {
        if (item.target === document.documentElement || item.target === document.head ||
            [...item.addedNodes].some(node => node.nodeType === 1 &&
              (node.matches("head, link[rel~=manifest], meta[name=application-name]") ||
               node.querySelector("link[rel~=manifest]")))) {
          queue();
          return;
        }
      } else if (item.target.matches("link[rel~=manifest], meta[name=application-name]")) {
        queue();
        return;
      }
    }
  });

  if (document.documentElement) {
    observer.observe(document.documentElement, {
      subtree: true,
      childList: true,
      attributes: true,
      attributeFilter: ["rel", "href", "content"]
    });
  }
  ensureInstallMetadata();
})();
