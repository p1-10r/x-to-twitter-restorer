const test = require("node:test");
const assert = require("node:assert/strict");
const { replaceUiLabel, replacePageTitle, isXBrandLogoPath } = require("../extension/brand-rules.js");

test("ブランド専用のUIラベルだけ変換する", () => {
  assert.equal(replaceUiLabel("X"), "Twitter");
  assert.equal(replaceUiLabel("  X  "), "  Twitter  ");
  assert.equal(replaceUiLabel("𝕏"), "Twitter");
  assert.equal(replaceUiLabel("About X"), "About Twitter");
  assert.equal(replaceUiLabel("Join X today."), "Join Twitter today.");
  assert.equal(replaceUiLabel("Xについて"), "Twitterについて");
  assert.equal(replaceUiLabel("Xでポスト"), "Twitterでポスト");
});

test("任意の投稿文章・ドメイン・小文字xは変換しない", () => {
  for (const text of [
    "I like X and x", "X is a variable", "Xを買った", "Xさん",
    "x", "x.com", "https://x.com/home", "RT @user: X",
    "my X account", "X marks the spot"
  ]) assert.equal(replaceUiLabel(text), text);
});

test("タイトルの末尾だけ変えて投稿内の X は残す", () => {
  assert.equal(replacePageTitle("Home / X"), "Home / Twitter");
  assert.equal(replacePageTitle("『X』という映画 / X"), "『X』という映画 / Twitter");
  assert.equal(replacePageTitle("X / Settings / X"), "X / Settings / Twitter");
  assert.equal(replacePageTitle("X - ホーム / Twitter", "/home"), "Twitter - ホーム / Twitter");
  assert.equal(replacePageTitle("X - Home / X", "/home"), "Twitter - Home / Twitter");
  assert.equal(replacePageTitle("X - 最高だった / X", "/someone/status/123"), "X - 最高だった / Twitter");
  assert.equal(replacePageTitle("X.com のご案内"), "X.com のご案内");
  assert.equal(replacePageTitle("X. It’s what’s happening / X"), "Twitter. It’s what’s happening / Twitter");
});

test("X公式ロゴだけ識別し、閉じるボタンのXは識別しない", () => {
  assert.equal(isXBrandLogoPath("M18.901 1.153h3.68l-8.04 9.19"), true);
  assert.equal(isXBrandLogoPath("M18.901 1.153h3.68L14.54"), true);
  assert.equal(isXBrandLogoPath("M18.244 2.25h3.308l-8.1"), true);
  assert.equal(isXBrandLogoPath("M18.244 2.25h3.308L14"), true);
  assert.equal(isXBrandLogoPath("M6 6l12 12M18 6L6 18"), false);
  assert.equal(isXBrandLogoPath("M23.953 4.57a10"), false);
});
