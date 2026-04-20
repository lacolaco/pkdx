---
name: yakkun-fetch
description: "yakkun.com (ポケモン徹底攻略) のパーティ構築ページから 6 体チーム情報を抽出し、box/teams/ に別名で登録するローカルスキル。yakkun URL (https://yakkun.com/bbs/party/...) を渡された時、「参考チーム登録」「yakkun チーム取り込み」等の質問時に使用。"
allowed-tools: Bash, Read, Write, AskUserQuestion
---

# yakkun.com Party Fetch (Local Skill)

yakkun.com のパーティ構築ページを取り込み、pkdx team cache 形式として登録するローカル拡張スキル。

**このスキルはローカル専用**。upstream (pkdxtools/pkdx) には存在しないため、self-update 実行時にもファイル単位で新規扱いとなり衝突しない (同名のスキルが upstream に追加されない限り安全)。

## パス定義

```
SKILL_DIR=（このSKILL.mdが置かれたディレクトリ）
REPO_ROOT=$SKILL_DIR/../../..
PKDX=$REPO_ROOT/bin/pkdx
```

## Phase 0: URL 取得 + 環境確認

### 0-1: URL 確認

ユーザー入力に yakkun.com のパーティ構築 URL (`https://yakkun.com/bbs/party/nXXXX` 等) が含まれているか確認。
含まれない場合は AskUserQuestion で URL を求める。

### 0-2: 軸名 (別名) 決定

AskUserQuestion で axis 名を決定。デフォルト候補:
- `参考<元軸>` (元チームが 自作 `マフォクシー-build-*` 等で既存なら `マフォクシー参考` のように付加)
- `rate2000-<ポケモン>` (レート明記)
- 自由入力

## Phase 1: ページダウンロード + 文字コード変換

yakkun.com は EUC-JP。curl で取得 → iconv で UTF-8 に変換。

```bash
curl -sL -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" \
  "<URL>" -o /tmp/yakkun_raw.html

iconv -f EUC-JP -t UTF-8 /tmp/yakkun_raw.html > /tmp/yakkun.html
```

### エラー処理
- curl 失敗 (非 200) → URL 再確認を依頼し終了
- iconv 失敗 → ページが UTF-8 直出力の可能性、`cp /tmp/yakkun_raw.html /tmp/yakkun.html` で代替

## Phase 2: 6 体セクション抽出

HTML の `id="pokemon-1"` 〜 `id="pokemon-6"` を境界にセクション分割。
HTML タグを除去してテキスト化:

```python
import re
html = open('/tmp/yakkun.html').read()
sections = []
for idx in range(1, 7):
    start = html.find(f'id="pokemon-{idx}"')
    if start < 0: continue
    end = html.find(f'id="pokemon-{idx+1}"', start) if idx < 6 else len(html)
    section = html[start:end][:5000]
    text = re.sub(r'<script.*?</script>', '', section, flags=re.DOTALL)
    text = re.sub(r'<style.*?</style>', '', text, flags=re.DOTALL)
    text = re.sub(r'<[^>]+>', ' ', text)
    text = re.sub(r'\s+', ' ', text).strip()
    sections.append(text)
```

## Phase 3: 各ポケモンのフィールド抽出

各セクションから以下を正規表現で抽出:

- **ポケモン名**: セクション先頭の `(メガ)?<カタカナ>` (最初のトークン)
- **持ち物**: `@ <item名>` の直後
- **性格**: `( <性格> )` 内
- **特性**: 性格の直後に続くトークン
- **SP (Champions 新仕様)**: `HP:N / 攻撃:N / ...` パターン。表記は `HP:<0-32> / 攻撃:<0-32> / ...`
- **実数値**: `実数値: N1 - N2 -N3 - N4 - N5 - N6`
- **技**: `能力ポイント` 以前のテキストから 4 つの技名。末尾の 4 技を抽出

注意点:
- 「252 表示」値は旧 SV レギュの努力値換算。Champions で保存するのは **SP (0-32)** の方
- Mega 形 (例 "メガマフォクシー") は pkdx DB では非メガと区別が必要。base_stats はメガ形で記録

## Phase 4: DB 照合と補完

各ポケモンで `pkdx query <name> --version champions` で DB 照合。
メガ形の場合は非メガ名で query (`マフォクシー` など) してから mega base_stats を適用:

| ポケモン | 非メガ base | メガ base (Champions DB より) |
|---|---|---|
| Mマフォクシー | 75/69/72/114/100/104 | 75/103/90/159/125/134 |
| Mメガニウム | 100/82/100/83/100/80 | 80/92/115/143/115/80 |
| Mルカリオ | 70/110/70/115/70/90 | 70/145/88/140/70/112 |
| (他 M\*) | DB 参照 | DB 参照 |

技は `pkdx moves <name> --version champions` で priority / stat_effects を補完。

## Phase 5: SP 逆算検証

実数値 6 個から `pkdx stat-reverse <name> --stats "H,A,B,C,D,S" --version champions` で性格・SP 配分を検証。
ユーザー入力の SP と DB 逆算結果を突合:
- 一致 → OK
- 不一致 → ユーザー入力値を信頼し警告のみ表示

## Phase 6: cache 組み立て

```json
{
  "battle_format": "singles",
  "mechanics": "メガシンカ",
  "version": "champions",
  "regulation": "M-A",
  "phase": 8,
  "members": [/* 6 members */],
  "coverage": [],
  "defense_matrix": [],
  "matchup_plans": [],
  "strengths": ["出典: <URL>", ...],
  "weaknesses": [],
  "updated_at": ""
}
```

`strengths[0]` には必ず **出典 URL + 取得日** を記録 (参照チームの追跡用)。

## Phase 7: md 出力

```bash
cat <cache.json> | $PKDX write teams --date "$(date +%F)" --axis "<決定した別名>"
```

ファイル出力先: `box/teams/<軸名>-build-<YYYY-MM-DD>.md`

## Phase 8: commit/push 確認

AskUserQuestion:

| # | 質問 | header | オプション |
|---|------|--------|-----------|
| 1 | 参考チームを git にコミット & push しますか？ | git操作 | はい(desc: 即commit&push), いいえ(desc: ローカル保存のみ) |

「はい」なら:
```bash
git add box/teams/<ファイル>.md box/teams/<ファイル>.meta.json
git commit -m "add: <軸名>チーム (yakkun.com <URL末尾>)"
git push -u origin <現ブランチ>
```

## self-update との衝突回避

- このスキルは **upstream に存在しない新規ファイル**として追加される
- self-update の Phase 1-3 コンフリクト処理は「同名ファイルのコンフリクト」にのみ反応するため、新規ファイルは影響なし
- 万が一 upstream が `yakkun-fetch` スキルを追加した場合、self-update の規則で `theirs` (upstream 版) に上書きされ本スキルが失われる
  - その場合は元の yakkun-fetch スキルを別名に改名して退避するか、自分用にマージ処理をカスタム

**絶対に修正してはいけないファイル** (upstream 管理):
- `.claude/skills/{breed,calc,nash,self-update,team-builder}/`
- `CLAUDE.md` (ルート)
- `pkdx/` 以下
- `pkdx_patch/`
- `setup.sh` / `scripts/`

本スキルはこれらに触らないため、self-update の動作に影響しない。

## サンプル実行

```bash
# URL: https://yakkun.com/bbs/party/n7112
# 1. ダウンロード
curl -sL -A "Mozilla/5.0" "https://yakkun.com/bbs/party/n7112" | iconv -f EUC-JP -t UTF-8 > /tmp/yakkun.html

# 2. Python パース (Phase 2-6 の組み合わせ)
python3 parse_yakkun.py /tmp/yakkun.html > /tmp/cache.json

# 3. md 出力
cat /tmp/cache.json | bin/pkdx write teams --date 2026-04-17 --axis マフォクシー参考
```

## エラーハンドリング

| 状況 | 対応 |
|------|------|
| curl が 403/404 | URL 確認を求める、User-Agent を明示して再試行 |
| セクション 6 つ未満 | ページ構造変化の可能性、手動パースに切り替える案内 |
| ポケモン名が DB に無い | リージョンフォーム (アローラ、ガラル等) の可能性 → ユーザー入力確認 |
| 技が Champions 非対応 | pkdx moves で確認、代替技提案 |
| SP 逆算不一致 | ユーザー入力値優先、stat-reverse 結果を警告表示 |
