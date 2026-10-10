# Twitter Blue Bird Restorer 1.4.3 🐦

Windows 10/11 + Brave 向け。x.com の **Twitter表記と青い鳥** を復活させる拡張機能と、PWAのアプリ名・アイコンをTwitterにするセットアップキットです。ツイート本文・ユーザー名・プロフィール・入力欄は変更しません。

## まず試す（ZIPだけで動作するモード）

1. ZIP を展開して、**`Start-Twitter-Setup.cmd`** をダブルクリックします。PowerShell は終了時も開いたままです。
2. スクリプトは、以前のインストール記録とポリシーを照合し、**このキットが所有するポリシーだけ**を一時解除します。Braveに解除を反映してから再登録するため、Braveを通常終了・再起動させてPWAの登録を待ちます。Windowsの別の管理ポリシーがあるときは停止します。
3. 表示された `%LOCALAPPDATA%\TwitterBlueBirdRestorer\Extension` を、`brave://extensions` → **デベロッパーモード** → **パッケージ化されていない拡張機能を読み込む** で**最初の1回だけ**選択します。
4. `brave://apps` から Twitter を起動。デスクトップのショートカットはBraveが作成し、必要ならスクリプトが補完します。タスクバーには起動中アイコンを右クリックして **タスクバーにピン留め** を選択します。
5. タスクバーの鳥が小さければ **`Start-Twitter-Taskbar-Fix.cmd`**。以前発生した `$Matches` / ハッシュテーブル衝突は修正済みです。ピン留め後に実行してください。戻すには `scripts\Undo-Twitter-Taskbar.ps1` を利用できます。

このキットにはGitHub公開先が事前設定されています。初回GitHub Releaseの公開前は、最新版の取得に失敗した場合に同梱拡張機能を使用します。GitHubのアイコンURLをポリシーが参照するため、GitHubにコードを公開する前はPWAセットアップを実行しないでください。まず `Start-Twitter-Publish.cmd` で公開し、Actionsのリリース完了後に `Start-Twitter-Setup.cmd` を実行してください。

## v1.4.3: 公開エラー修正

Windows PowerShell 5.1で `manifest.json` の日本語が文字化けしてJSON解析に失敗する問題を修正しました。`Publish-Twitter-GitHub.ps1` はUTF-8として厳密に読み込み、拡張機能の `manifest.json`、PWAマニフェスト、`config.json` をGitHubへの送信前に検証します。コマンドの引数渡しも明示化しています。

v1.4.2で `ERROR: ':' または '}' ...` が出た場合、**v1.4.3のZIPを新しく解凍して** `Start-Twitter-Publish.cmd` を再実行します。GitHub CLIへ再ログインする必要はありません。公開成功後は、[GitHub Actions](https://github.com/p1-10r/x-to-twitter-restorer/actions) で `v1.4.3` のリリース処理が成功したか確認してください。すでにv1.4.2を公開している場合も、v1.4.3は別タグとして公開できます。

## GitHub公開と自動更新

GitHub公開先は `p1-10r/x-to-twitter-restorer` に設定済みです。`Start-Twitter-Publish.cmd` を実行し、そのまま Enter（空欄）か `x-to-twitter-restorer` と入力できます。Git for Windows / GitHub CLI (`gh`) がなければ、実行時に `INSTALL` の確認を受けて `winget` でインストールします。GitHubログインが必要ならブラウザを開いて認証を案内します。**公開済みの `p1-10r/x-to-twitter-restorer` リポジトリ**に、拡張機能・セットアップ・アイコン・GitHub Actions定義をアップロードします（リポジトリ自体の新規作成はしません）。**公開の最終確認 (`PUBLISH`) が必要**です。

- タグ `v1.4.3` をアップロードすると、GitHub Actions がリリース `twitter-extension.zip` と `twitter-extension.zip.sha256` に加え、セットアップ全体の `twitter-restorer-kit.zip` も生成します。
- GitHubにリリースができたら、`Start-Twitter-Bootstrap.cmd` をダブルクリックするか、もう一度 `Start-Twitter-Setup.cmd` を実行します。設定済みの `config.json` を使い、最新リリースを取得してSHA-256を照合します。
- 同時に、ユーザーのタスクスケジューラに **毎日9:00** の更新確認を登録します。更新時は安定したフォルダ内の拡張機能ファイルを更新します。**有効化にはBraveの再起動／拡張機能の再読み込みが必要**です。閲覧中のBraveを自動終了させません。
- `Start-Twitter-Update.cmd` を実行すれば、手動で今すぐ最新版を確認できます。
- GitHub公開後は、`Bootstrap-Twitter.ps1`（引数なしでも可）または `Start-Twitter-Bootstrap.cmd` で最新キットを取得してセットアップを起動できます（ブラウザの初回承認は別途必要）。
- `config.json` の `github_repo` に `owner/repository` を手動設定する方法もあります。GitHub公開済みのリポジトリで指定してください。

更新は一般公開されたGitHub Releasesを利用するため、公開リポジトリが必要です。**単純なGitHub上の未公開Chrome拡張機能を、普通の個人PCへ完全無人で初回インストールすることはできません。** Chrome/Braveの管理対象環境やChrome Web Storeでの公開と異なり、最初の開発者モードでの承認が必要です。Windowsのタスクバー固定も環境により利用者の承認が必要です。スクリプトはこれらの制限を回避しません。

## スクリプト

| ファイル | 処理 |
| --- | --- |
| `Start-Twitter-Bootstrap.cmd` | GitHubの最新キットをダウンロード。失敗してもウィンドウを閉じずエラーを表示 |
| `Start-Twitter-Setup.cmd` | 拡張機能同期、所有済みPWAポリシーの更新、Brave再起動、デスクトップ登録、更新タスク作成 |
| `Start-Twitter-Update.cmd` | GitHubの最新版とSHA-256を確認し、拡張機能ファイルを更新 |
| `Start-Twitter-Taskbar-Fix.cmd` | ピン留め済みTwitterショートカットのアイコンを拡大版へ更新 |
| `Start-Twitter-Remove.cmd` | このキットのポリシーのみ削除（ブラウザ再起動が必要） |
| `Start-Twitter-Publish.cmd` | 公開GitHubリポジトリへの初回アップロードとタグ付け |

`WebAppInstallForceList` は、アプリを強制インストールするBraveのポリシーです。この設定中は、通常のアプリ一覧からTwitterをアンインストールできない場合があります。元に戻す際は `Start-Twitter-Remove.cmd` を先に使用してください。別プロファイルでも同じWindowsユーザーのポリシーが適用され得ます。

## テスト範囲

- Node.js のブランド置換テスト4件、拡張の構成/アセット検査、ZIP整合性検査を実施。
- Windows上のPowerShell 5.1、Brave実機での一括実行やGitHub Actionsの公開は、この制作環境からは実施できていません。`Bootstrap-Twitter.ps1` を直接実行すると PowerShell の起動方法によっては終了とともに窓が閉じるので、エラー確認には `Start-Twitter-Bootstrap.cmd` を使ってください。WindowsのバージョンやPWAキャッシュにより手順の補完が必要になる場合があります。

Twitter/Xの公式プロダクトではありません。
