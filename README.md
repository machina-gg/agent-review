# agent-review

GitHub Actions 上の Claude が Pull Request をレビューし、判定行が `判定: APPROVE` のときだけ
`github-actions[bot]` が Approve を押す **reusable workflow** と、その**レビュー観点**を置く共有リポジトリ。

複数のリポジトリが同じ観点・同じ判定の契約でレビューを受けられるようにするためのもので、
観点と Approve スクリプトの実体はここ 1 箇所にある。

## 呼び方

呼び出し元リポジトリに次のワークフローを置く。

```yaml
name: Claude Review

on:
  pull_request:
    types: [opened, synchronize, reopened, ready_for_review]

concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  review:
    uses: machina-gg/agent-review/.github/workflows/review.yml@main
    permissions:
      contents: read
      pull-requests: write
      issues: write
    with:
      profile: chrome-extension
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

- **`on` は `pull_request` であること。** ジョブの実行可否（draft を除外する等）は
  `github.event.pull_request` を見て決めるため、他のイベントでは動かない
- `with.profile` は**省略できる**（省略時は `perspectives/common.md` だけを読む）。
  カンマ区切りで複数指定できる（例: `profile: harness,chrome-extension`）
- `secrets.CLAUDE_CODE_OAUTH_TOKEN` は**必須**（呼び出し元が明示的に渡す）。
  値が空（repo secret 未登録）の場合は警告を出して skip し、**job は成功で終わる**
  （レビューコメントと Approve は付かない）

### 呼び出し元に必要な permissions

呼ばれる側は、**呼び出し元が与えた権限以下しか宣言できない**
（公式ドキュメント: [Reuse workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows)
「permissions can only be maintained or reduced—not elevated—throughout the chain」）。
呼び出し元の job に次の 3 つを与えること。

| 権限                   | 何に要るか                      |
| ---------------------- | ------------------------------- |
| `contents: read`       | 呼び出し元リポジトリの checkout |
| `pull-requests: write` | Approve（reviews API）          |
| `issues: write`        | レビューコメントの投稿          |

さらにリポジトリ設定の **Actions → General → Workflow permissions** で
「Allow GitHub Actions to create and approve pull requests」が有効である必要がある
（無効だと Approve の POST が `Resource not accessible by integration` で失敗する）。

### secret の用意

`CLAUDE_CODE_OAUTH_TOKEN` は `claude setup-token` で発行し、呼び出し元リポジトリの
repository secret に登録する（リポジトリ管理者の作業）。

## プロファイル

`perspectives/<name>.md` が 1 プロファイル。`common.md` は**常に**読まれ、`profile` で指定したものが**足される**。

| profile            | 対象                                                                    |
| ------------------ | ----------------------------------------------------------------------- |
| （指定なし）       | `common.md` だけ。どのリポジトリでも通用する最小の観点                  |
| `harness`          | エージェントの運営ルール文書・CI 定義・自動化スクリプトを持つリポジトリ |
| `chrome-extension` | Chrome 拡張（Manifest V3）                                              |

上の表にない技術スタック（静的サイトジェネレータ・Web アプリのフレームワーク等）の
プロファイルは**まだ作っていない**。指定しない（`common.md` だけで運用する）か、
このリポジトリに追加する。**存在しないプロファイルを指定した場合はそのファイルが無視され、
レビュー本文の `未解決:` にその旨が書かれる**（job は失敗しない）。

## 判定行の契約

レビューは `gh pr comment` のコメント 1 件として投稿され、その本文の形が Approve の契約になる。

- 本文に `## レビュー(reviewer)` の見出しがあること
- **コードブロックの外に、行頭 `判定: ` で始まる行がちょうど 1 本**あること
- 値は `APPROVE` または `REQUEST_CHANGES`

`scripts/approve-if-verdict.sh` は、`github-actions[bot]` が job 開始時刻以降に投稿したコメントの中から
この形を探し、`判定: APPROVE` で、かつ PR の head SHA がレビュー時点から動いていないときだけ Approve を押す。
形式の詳細は [`perspectives/common.md`](perspectives/common.md)「レビュー結果の定型フォーマット」が SSOT。

⚠ **同じ形式を人間や他の bot が投稿しても Approve は付かない**（投稿者を `github-actions[bot]` に固定しているため）。
これがこの仕組みの要で、回帰テスト（`tests/approve-if-verdict.test.sh`）が固定している。

## `.agent-review/` の改竄検査

`review.yml` は、このリポジトリの `main` を呼び出し元のワークスペースの `.agent-review/` に checkout してから
Claude を走らせる。Claude には `Write` を許しているため、Approve を押す前に

```
git -C .agent-review diff --quiet HEAD -- .
```

で checkout 時点から変わっていないことを検査し、**変わっていれば Approve を押さずに run を失敗させる**（fail-close）。

⚠ **checkout の ref は `main` 固定**。呼び出し元の PR が観点や Approve スクリプトを差し替えてから
自分をレビューさせる経路を作らないため、PR で `perspectives/` を変更しても、その PR 自身のレビューには反映されない
（`main` にマージされてから効く）。

## 塞いでいないもの

- **`@main` 参照は可変**。このリポジトリの `main` が変わると、呼び出し元すべてに即時反映される。
  SHA 固定は採らず、このリポジトリ側をルールセットとレビューで守る
- **呼び出し元の PR が自分の workflow 定義を変えて自己 Approve できる**（`pull_request` は PR 側の定義を実行するため）。
  `.yml` を変更する PR を人間がマージする運用で守る

## このリポジトリを変更するとき

- **public リポジトリである。** 秘密・内部事情（トークン・個人のローカルパス・非公開の運用詳細）を書かない
- `scripts/` と `.github/workflows/` の変更は、**レビューを人間が確認したうえで人間がマージする**
- 詳細は [`CLAUDE.md`](CLAUDE.md)

## ディレクトリ構成

| パス                                  | 役割                                                  |
| ------------------------------------- | ----------------------------------------------------- |
| `.github/workflows/review.yml`        | reusable workflow（本体）                             |
| `.github/workflows/claude-review.yml` | このリポジトリ自身の PR をレビューする呼び出し元      |
| `.github/workflows/ci.yml`            | このリポジトリ自身の CI（shellcheck / テスト / 整形） |
| `scripts/approve-if-verdict.sh`       | 判定行を読んで Approve を押す                         |
| `tests/approve-if-verdict.test.sh`    | 上記の回帰テスト（`gh` をスタブに差し替えて走る）     |
| `perspectives/`                       | レビュー観点（`common.md` + プロファイル）            |

## ローカルでの検査

```bash
git ls-files '*.sh' | xargs shellcheck
bash tests/approve-if-verdict.test.sh
npx prettier@3 --check .
```
