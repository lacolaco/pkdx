# box/meta/ — M-1 レギュレーション制約・環境メモ

**重要**: `m1-constraints.md` はアイテム・技・メガ・特性の M-1 使用可否を記録したドキュメント。
**構築提案・技変更・アイテム提案を行う前に必ず Read すること**。

## 運用ルール

1. **提案前チェック**: アイテム/技/メガ/特性を含む提案をする時は、`m1-constraints.md` の「提案前チェックリスト」に従う
2. **観測ベース**: 使用可の確証が無いもの (canonical SV 知識 等) は提案しない
3. **DB 照合**: `pkdx query`, `pkdx moves` で都度確認する習慣

## ファイル一覧

- `m1-constraints.md` — Champions M-A / M-1 レギュレーション制約の中央ドキュメント
- `README.md` (本ファイル) — メタ ディレクトリの案内

## 更新方針

制約違反の提案ミスが発生した場合、即座に `m1-constraints.md` に追記し再発防止する。

## 関連スキル

- `.claude/skills/yakkun-fetch/` — 参考チーム取り込み (本制約を事前参照)
- `.claude/skills/yakkun-ranking/` — 使用率ランキング
