/*
 * 画面の固定UIにだけ適用するブランド名の置換ルール。
 * グローバルな置換にしないことで、ポスト・アカウント名への影響を防ぐ。
 */
(function (scope) {
  "use strict";

  const EXACT_LABELS = new Map([
    ["X", "Twitter"],
    ["𝕏", "Twitter"],
    ["About X", "About Twitter"],
    ["About X Corp.", "About Twitter Corp."],
    ["X Premium", "Twitter Premium"],
    ["X for Business", "Twitter for Business"],
    ["X for Developers", "Twitter for Developers"],
    ["X Developers", "Twitter Developers"],
    ["X Help Center", "Twitter Help Center"],
    ["X Corp.", "Twitter Corp."],
    ["Sign in to X", "Sign in to Twitter"],
    ["Log in to X", "Log in to Twitter"],
    ["Welcome to X", "Welcome to Twitter"],
    ["Join X", "Join Twitter"],
    ["Join X today", "Join Twitter today"],
    ["Join X today.", "Join Twitter today."],
    ["Share on X", "Share on Twitter"],
    ["Follow on X", "Follow on Twitter"],
    ["Post on X", "Post on Twitter"],
    ["Search X", "Search Twitter"],
    ["Xについて", "Twitterについて"],
    ["Xにログイン", "Twitterにログイン"],
    ["Xへようこそ", "Twitterへようこそ"],
    ["Xに登録", "Twitterに登録"],
    ["Xに参加", "Twitterに参加"],
    ["Xを始めよう", "Twitterを始めよう"],
    ["Xで共有", "Twitterで共有"],
    ["Xでポスト", "Twitterでポスト"],
    ["Xにポスト", "Twitterにポスト"],
    ["Xの利用規約", "Twitterの利用規約"],
    ["Xのプライバシーポリシー", "Twitterのプライバシーポリシー"],
    ["Xのヘルプセンター", "Twitterのヘルプセンター"]
  ]);

  // 文字列の前後の空白は、DOM上のレイアウト維持のためそのまま残す。
  function replaceUiLabel(value) {
    if (typeof value !== "string" || !value.includes("X") && !value.includes("𝕏")) {
      return value;
    }
    const match = /^(\s*)([\s\S]*?)(\s*)$/.exec(value);
    if (!match) return value;
    const replacement = EXACT_LABELS.get(match[2]);
    return replacement === undefined ? value : match[1] + replacement + match[3];
  }

  // ページタイトルにはポスト本文が含まれることがあるので、末尾のサービス名だけを変更する。
  function replacePageTitle(title, pathname = "") {
    if (typeof title !== "string") return title;
    if (title === "X" || title === "𝕏") return "Twitter";
    let changed = title.replace(/(\s[\/|｜]\s)(?:X|𝕏)$/, "$1Twitter");
    // ホーム等の公式画面に限り「X - ホーム / Twitter」の先頭もブランド名として扱う。
    // 投稿個別ページでは投稿本文がページタイトルに使われるため一切触れない。
    if (["/home", "/explore", "/notifications", "/messages", "/i/bookmarks", "/settings"].includes(pathname)) {
      changed = changed.replace(/^(?:X|𝕏)(?= - )/, "Twitter");
    }
    return changed.replace(/^X\. (It['’]s what['’]s happening)(?= \/ Twitter$)/, "Twitter. $1");
  }

  // Xの公式シンボルのSVGパス。他の「閉じる」などのXアイコンには触らない。
  function isXBrandLogoPath(pathData) {
    if (typeof pathData !== "string") return false;
    const data = pathData.trim();
    // 実際のXロゴは「h3.68l-8.04...」のように小文字の l で続く。
    // 旧判定の \b は数字とアルファベットの間ではマッチしなかった。
    return /^M18\.901[\s,]+1\.153h3\.68(?:[lL]|$)/.test(data) ||
      /^M18\.244[\s,]+2\.25h3\.308(?:[lL]|$)/.test(data);
  }

  const api = Object.freeze({ replaceUiLabel, replacePageTitle, isXBrandLogoPath });
  scope.TwitterBrandRules = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})(globalThis);
