#!/bin/bash
# 素の bash テストランナー用の最小アサーションライブラリ。
# 外部依存（bats 等）を導入しない方針のため、必要最小限の機能だけを持つ。
#
# 使い方（テストファイル側）:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/assert.sh"
#   assert_contains "$OUT" "期待文字列" "説明"
#   finish   # 末尾で呼ぶ。失敗が1件でもあれば exit 1

# 集計用カウンタ
TESTS_PASSED=0
TESTS_FAILED=0

# 色は CI ログでも読めるよう最小限（TTY 以外では無効化）
if [[ -t 1 ]]; then
  C_OK=$'\033[32m'
  C_NG=$'\033[31m'
  C_RESET=$'\033[0m'
else
  C_OK=""
  C_NG=""
  C_RESET=""
fi

# 成功を記録する
pass() { # $1 = 説明
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo "  ${C_OK}✓${C_RESET} $1"
}

# 失敗を記録する（詳細は複数行で受け取る）
fail() { # $1 = 説明, $2... = 詳細
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo "  ${C_NG}✗${C_RESET} $1"
  shift
  local line
  for line in "$@"; do
    echo "      $line"
  done
}

# 文字列が部分一致で含まれることを検証する
assert_contains() { # $1 = 対象, $2 = 期待部分文字列, $3 = 説明
  if [[ "$1" == *"$2"* ]]; then
    pass "$3"
  else
    fail "$3" "期待: 「$2」を含む" "実際の出力は下記:" "$1"
  fi
}

# 文字列が部分一致で含まれないことを検証する
assert_not_contains() { # $1 = 対象, $2 = 含まれてはならない文字列, $3 = 説明
  if [[ "$1" != *"$2"* ]]; then
    pass "$3"
  else
    fail "$3" "期待: 「$2」を含まない" "実際の出力は下記:" "$1"
  fi
}

# 完全一致を検証する
assert_equals() { # $1 = 実際, $2 = 期待, $3 = 説明
  if [[ "$1" == "$2" ]]; then
    pass "$3"
  else
    fail "$3" "期待: 「$2」" "実際: 「$1」"
  fi
}

# ディレクトリが存在することを検証する
assert_dir_exists() { # $1 = パス, $2 = 説明
  if [[ -d "$1" ]]; then
    pass "$2"
  else
    fail "$2" "存在するはずのディレクトリがありません: $1"
  fi
}

# ディレクトリが存在しないことを検証する
assert_dir_absent() { # $1 = パス, $2 = 説明
  if [[ ! -d "$1" ]]; then
    pass "$2"
  else
    fail "$2" "削除されるはずのディレクトリが残っています: $1"
  fi
}

# テストファイルの末尾で呼び、結果に応じた終了コードを返す
finish() {
  echo ""
  echo "  結果: ${TESTS_PASSED} passed / ${TESTS_FAILED} failed"
  if [[ "$TESTS_FAILED" -gt 0 ]]; then
    return 1
  fi
  return 0
}
