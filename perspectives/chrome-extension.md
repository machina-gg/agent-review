# chrome-extension プロファイル

Chrome 拡張機能（Manifest V3）のリポジトリ向けの観点。`common.md` に足して適用する。

## 権限（最重要）

拡張の権限はユーザーに一度しか見えず、増えたことに気付かれにくい。**差分で増える権限は必ず止めて理由を問う。**

- `manifest.json` の `permissions` / `optional_permissions` / `host_permissions` に**追加**がある場合、
  PR 本文か Issue に「その権限で何をするか」が書かれているか。書かれていなければ修正必須
- `host_permissions` が `<all_urls>` や `*://*/*` になっていないか。
  実際に必要なオリジンに絞れないか（絞れるなら修正必須）
- 常時付与ではなく `optional_permissions` + `chrome.permissions.request()`（実行時要求）で
  足りないか検討されているか
- `activeTab` で足りる操作に `tabs` / `scripting` の恒常権限を取っていないか
- `content_scripts` の `matches` が必要以上に広くないか

## CSP とコード実行

- `content_security_policy` を緩めていないか（`unsafe-eval` / `unsafe-inline` / 外部ホストの追加は修正必須。
  緩める場合は代替手段を検討した記録が要る）
- リモートコードを読み込んでいないか（Manifest V3 は外部ホストのスクリプト実行を認めない）
- `innerHTML` / `insertAdjacentHTML` に外部由来の文字列を渡していないか（DOM ベース XSS）
- Web ページ（content script の実行先）から受け取るメッセージ・DOM の値を、検証せずに
  特権のある側（background / service worker）へ渡していないか
- `externally_connectable` の対象が広すぎないか

## `chrome.storage`

- **read-modify-write の競合**: 複数のコンテキスト（popup / content script / service worker）が
  同じキーを読んで書き戻す形になっていないか。後勝ちで更新が消える
- 保存形式の変更（キー名・構造）に対して、**旧データを読んだときの振る舞い**が決まっているか
  （マイグレーション、または既定値へのフォールバック）
- **起動直後の hydration**: `chrome.storage` は非同期のため、読み込み完了前に UI が既定値で描画され、
  そのあと保存済みの値で上書きされる。この「一瞬だけ既定値が見える」形と、
  読み込み完了前の書き込みによる**保存済み設定の踏み潰し**が起きていないか
- `sync` と `local` の選択が意図的か（`sync` には容量・書き込み回数の制限がある）
- 秘匿情報（トークン等）を平文で `storage` に置いていないか

## Service Worker（background）のライフサイクル

- **状態を持たせていないか。** Manifest V3 の service worker はアイドルで停止し、
  グローバル変数・モジュールスコープの変数は失われる。状態は `chrome.storage` 等の永続層に置く
- `setTimeout` / `setInterval` による長時間の待ちに依存していないか（`chrome.alarms` を使う）
- トップレベルで一度だけ実行される前提のコードが、再起動のたびに走っても壊れないか
  （イベントリスナーの登録はトップレベルで同期的に行う必要がある）
- 非同期処理の完了前に worker が停止しないか（メッセージハンドラの `return true` / Promise の扱い）

## テスト

- **E2E は外部サイトへ出ない。** 実在の Web サイトを開いて操作するテストは、相手の変更・障害・
  レート制限で壊れ、こちらの CI を相手に依存させる。ローカルのフィクスチャページを使っているか
- 拡張の権限・manifest を変更した PR に、その変更を踏むテストがあるか
- ネットワークアクセスをモックしているか（CI がオフラインでも通るか）
