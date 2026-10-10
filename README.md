# Twitter Blue Bird Restorer 🐦

X（x.com）を、青い鳥の「Twitter」の見た目に戻すWindows用ツールです。**Chrome / Edge / Brave** に対応します。ツイート本文、ユーザー名、プロフィール、入力中の文字は書き換えません。

## インストール

1. [最新のリリース](https://github.com/p1-10r/x-to-twitter-restorer/releases/latest) から `twitter-restorer-kit.zip` をダウンロードして解凍します。
2. `Start-Twitter-Setup.cmd` をダブルクリックします（最新版をGitHubから取得する場合は `Start-Twitter-Bootstrap.cmd`）。
3. Windowsの管理者確認が表示されたら、変更内容を確認して承認してください。
4. 既定ブラウザを自動検出します。対象外の場合は Chrome / Edge / Brave から選択できます。
5. 画面に表示された変更内容を読み、同意する場合に `REINSTALL` と入力します。
6. **拡張機能がすでに有効か自動確認**します。入っていない場合のみ、表示された拡張機能画面でデベロッパーモードを有効にし、「パッケージ化されていない拡張機能を読み込む」から画面に表示されたフォルダを指定してください。Enterで登録状態を再確認します。
7. 既存のTwitter/Xアプリがあればアンインストール確認が出ます。「閲覧データも削除」を選ばないでください。青い鳥のアプリを再登録し、デスクトップショートカットを作成します。タスクバー固定にはWindowsの操作が必要な場合があります。

> ブラウザの拡張機能の初回読み込みは、ブラウザの許可画面が必要です。自動セットアップでも無断で登録することはできません。

## 変更されること

- x.com内の公式ロゴ、favicon、サービス名の表示、タイトル
- WindowsのPWA登録ポリシー (`WebAppInstallForceList`)、デスクトップ・タスクバーのショートカット
- 毎日の拡張機能更新確認タスク（最新版を確認し、ブラウザの再読み込みが必要になる場合があります）
- PWA/ショートカットに使用する青い鳥アイコンは、背景透過の画像です。

変更前に画面で確認を求めます。Cookie、サイトデータ、ログイン情報、閲覧履歴を削除する処理は行いません。既存PWAを削除するときも、ブラウザの閲覧データ削除を選択しないでください。

## よくある質問

**拡張機能がインストールされない**：`chrome://extensions` / `edge://extensions` / `brave://extensions` で「Twitter Blue Bird Restorer」が有効か確認してください。Windowsユーザーのブラウザプロファイル単位で登録が必要です。

**アイコンが古いまま**：一度アプリのピン留めを解除し、新しくインストールされたTwitterを起動してピン留めし直してください。アイコンのキャッシュ更新にWindowsのサインアウトが必要なことがあります。

**PowerShellが即終了する**：`.ps1` を直接ダブルクリックせず、同梱の `Start-Twitter-Setup.cmd` または `Start-Twitter-Bootstrap.cmd` を実行してください。

**アンインストール／設定の解除**：`Start-Twitter-Remove.cmd` を実行してください。拡張機能の削除は各ブラウザの拡張機能管理画面で行います。

## ダウンロード

[GitHub Releases](https://github.com/p1-10r/x-to-twitter-restorer/releases/latest)
