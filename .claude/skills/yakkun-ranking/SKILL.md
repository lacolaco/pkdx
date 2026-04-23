---
name: yakkun-ranking
description: "yakkun.com (ポケモン徹底攻略) Championsシングル使用率ランキングを取得し box/ranking/ に日付付きで保存するローカルスキル。「現環境の使用率」「ランキング更新」「yakkun ranking」「環境メタ確認」等の質問時に使用。"
allowed-tools: Bash, Read, Write, AskUserQuestion
---

# yakkun.com Champions Ranking Fetch (Local Skill)

yakkun.com の Champions シングル使用率ランキングページを取得・パースし、環境メタ情報として `box/ranking/` に保存する。

**ローカル専用スキル**。upstream には存在しないユニーク名 (`yakkun-ranking`) のため self-update と衝突しない。

## パス定義

```
SKILL_DIR=（このSKILL.mdが置かれたディレクトリ）
REPO_ROOT=$SKILL_DIR/../../..
URL=https://yakkun.com/ch/ranking.htm
OUTPUT=$REPO_ROOT/box/ranking/yakkun-$(date +%Y-%m-%d).md
```

## Phase 0: 既存データ確認

`box/ranking/` 配下に当日のファイルがあれば取得スキップしてそれを提示。
当日ファイルが無ければ Phase 1 へ。

```bash
TODAY=$(date +%Y-%m-%d)
FILE="$REPO_ROOT/box/ranking/yakkun-$TODAY.md"
if [ -f "$FILE" ]; then
  cat "$FILE"
  exit 0
fi
```

## Phase 1: ページダウンロード

yakkun は EUC-JP。curl + iconv で変換:

```bash
curl -sL -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" \
  "https://yakkun.com/ch/ranking.htm" -o /tmp/yakkun_ranking_raw.html
iconv -f EUC-JP -t UTF-8 /tmp/yakkun_ranking_raw.html > /tmp/yakkun_ranking.html
```

## Phase 2: ランキングパース

ポケモン名は `N位: <名前>` のパターンで埋め込まれている。正規表現で抽出:

```python
import re
html = open('/tmp/yakkun_ranking.html').read()
seen = {}
for m in re.finditer(r'(\d+)位: ([^"<]+)"', html):
    rank = int(m.group(1))
    name = m.group(2).strip()
    if rank not in seen:
        seen[rank] = name

# rank 順でソート
rows = sorted(seen.items())
```

**注意点**:
- 同じ順位が複数回出現する (トップバナー用 + メインリスト用)。dict で重複除去
- 26-28 位等の **欠番** が存在する場合あり (yakkun 側の表示仕様)。欠番は飛ばして記録
- `♂`/`♀` などフォーム識別子付きも保持 (例: `イダイトウ♂`)

## Phase 3: Markdown 出力

```markdown
# Champions シングル 使用率ランキング (yakkun.com)

**出典**: https://yakkun.com/ch/ranking.htm
**取得日**: 2026-04-18
**最終更新**: 2026-04-18T17:30:14+09:00 (ページメタデータから)

| 順位 | ポケモン |
|:---:|---|
| 1 | ガブリアス |
| 2 | アシレーヌ |
| 3 | メガリザードンY |
| 4 | アーマーガア |
| 5 | ブリジュラス |
| 6 | メガゲンガー |
| 7 | メガハッサム |
| 8 | カバルドン |
| 9 | ドドゲザン |
| 10 | ギルガルド |
| ... | ... |
```

ページメタデータ (`<meta property="article:modified_time" ...>`) から最終更新時刻も抽出して記録する。

## Phase 4: 保存

```bash
mkdir -p "$REPO_ROOT/box/ranking"
```

出力先: `box/ranking/yakkun-YYYY-MM-DD.md`

## Phase 5: commit/push 確認

AskUserQuestion:

| # | 質問 | header | オプション |
|---|------|--------|-----------|
| 1 | ランキングデータを git にコミット & push しますか？ | git操作 | はい(desc: 即commit&push), いいえ(desc: ローカル保存のみ) |

## self-update 衝突回避

- このスキルは **upstream に存在しないユニーク名** (`yakkun-ranking`) で新規ファイルとして追加される
- self-update の Phase 1-3 コンフリクト処理は既存ファイルの編集競合のみ対象のため、新規ファイルは影響なし
- 絶対に触らないファイル: `breed/calc/nash/self-update/team-builder/` 系スキル、`CLAUDE.md`、`pkdx/`、`pkdx_patch/`、`setup.sh`

出力先 `box/ranking/` は `box/` 配下 → self-update 時 `ours` 優先 → ユーザーデータとして保護される。

## 使い方例

```
ユーザー: "現環境の使用率は?"

スキル動作:
1. box/ranking/yakkun-2026-04-18.md 存在確認
2. 無ければ curl で yakkun 取得
3. ランキング表を md で保存
4. 上位 20 件を表示
5. commit&push 問う
```

## 発展機能 (任意)

- **過去ランキングとの比較**: 前回取得ファイルとの差分 (↑↓) 表示
- **自チーム登場率**: box/teams/*.meta.json の members とクロスチェックし「自チーム中 N 体がトップ 20 に該当」レポート
- **Nash meta-divergence との連動**: pkdx meta-divergence への入力として提供

これらは本スキル内で自動発火せず、ユーザーからの追加指示で行う。

## エラーハンドリング

| 状況 | 対応 |
|------|------|
| curl 403/404 | User-Agent を明示して再試行。ページ URL 変更可能性を告知 |
| パースで 0 件 | HTML 構造変更の可能性。生 HTML を保持して手動確認案内 |
| 欠番大量 | yakkun 側のデータ更新タイミング (月次) による可能性、注記して続行 |
