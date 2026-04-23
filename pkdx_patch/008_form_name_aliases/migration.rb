# 008_form_name_aliases — pokedex_name にフォーム別の一意な別名を投入
#
# Bug: `pkdx query ウォッシュロトム` や `pkdx query キュウコン（アローラ）` が
# Pokemon not found になる。pokedex_name.name は種族共通の名前しか持たず、
# pokedex_form.form にある形態別名 (ウォッシュロトム / アローラのすがた 等) を
# pkdx の検索経路が参照していないことが原因。002_champions_pokemon が mega 行に
# 対して pokedex_name を直接 INSERT しているのと同じ流儀で、フォーム違い全般を
# 投入する。
#
# 方針:
# - pokedex_form.form が原種名 (base species) を含むなら verbatim で使用
#   (例: "ウォッシュロトム" ⊃ "ロトム" → そのまま)
# - 含まない場合は "{species}（{form}）" に合成し name 単体で一意化
#   (例: "アローラのすがた" → "キュウコン（アローラ）")
#   "のすがた" / " Form" は情報量ゼロなので事前に剥ぐ
# - 戦闘面で差異のないフォーム (ビビヨン模様・フラベベ花色・Unown 文字・
#   トリミアン毛型・マホイップ flavor 等) は status/type/ability が base と
#   完全一致するかどうかを EXCEPT 比較で判定して除外 (ノイズ防止)
# - mega / gigantamax は out of scope (mega は 001/002 済、gmax は別 PR)
# - base id (_00000000_0_000_0) は触らない
# - pokedex_name.form / region は local_pokedex_status (language 非依存) から
#   持ってくる。これにより jpn 行と eng 行で同じ値になり、query_pokemon の
#   pne 自己結合 (form/region 一致条件) が成立する。また query_search /
#   query_learners の COALESCE(pn.form,'')='' フィルタが初めて機能するようになる

LANGS = %w[jpn eng].freeze

# 戦闘面で base と完全に同じ形態 = cosmetic なら true。
# 全 version 横断で local_pokedex_status / _type / _ability の EXCEPT が 0 件ならそう判定。
def form_cosmetic?(db, form_id, global_no)
  base_id = "#{global_no}_00000000_0_000_0"

  stat_diff = db.get_first_value(<<~SQL, [form_id, base_id]).to_i
    SELECT COUNT(*) FROM (
      SELECT version, hp, attack, defense, special_attack, special_defense, speed
        FROM local_pokedex_status WHERE id = ?
      EXCEPT
      SELECT version, hp, attack, defense, special_attack, special_defense, speed
        FROM local_pokedex_status WHERE id = ?
    )
  SQL
  return false if stat_diff > 0

  type_diff = db.get_first_value(<<~SQL, [form_id, base_id]).to_i
    SELECT COUNT(*) FROM (
      SELECT version, type1, COALESCE(type2, '') FROM local_pokedex_type WHERE id = ?
      EXCEPT
      SELECT version, type1, COALESCE(type2, '') FROM local_pokedex_type WHERE id = ?
    )
  SQL
  return false if type_diff > 0

  ab_diff = db.get_first_value(<<~SQL, [form_id, base_id]).to_i
    SELECT COUNT(*) FROM (
      SELECT version, COALESCE(ability1, ''), COALESCE(ability2, ''), COALESCE(dream_ability, '')
        FROM local_pokedex_ability WHERE id = ?
      EXCEPT
      SELECT version, COALESCE(ability1, ''), COALESCE(ability2, ''), COALESCE(dream_ability, '')
        FROM local_pokedex_ability WHERE id = ?
    )
  SQL
  return false if ab_diff > 0

  true
end

# id に対応する form / region 列の値 (language 非依存) を local_pokedex_status
# から取得。mega / gmax 行は除外し、form か region のどちらかに値が入っている
# バージョンの行を優先的に返す (Champions では form/region が空のダミー行になる
# ケースがあるため)。該当なしなら nil → skip。
def fetch_form_region(db, id)
  row = db.get_first_row(<<~SQL, [id])
    SELECT form, region
      FROM local_pokedex_status
     WHERE id = ?
       AND COALESCE(mega_evolution, '') = ''
       AND COALESCE(gigantamax, '')     = ''
       AND (COALESCE(form, '') != '' OR COALESCE(region, '') != '')
     LIMIT 1
  SQL
  return nil if row.nil?
  form, region = row
  [form.to_s, region.to_s]
end

inserted = 0
updated  = 0
skipped_cosmetic = 0
skipped_no_base  = 0
skipped_no_stats = 0
skipped_same_as_base = 0

LANGS.each do |lang|
  rows = db.execute(<<~SQL, [lang])
    SELECT pf.id, pf.globalNo, pf.form
      FROM pokedex_form pf
     WHERE pf.language = ?
       AND pf.form IS NOT NULL AND pf.form != ''
  SQL

  rows.each do |id, gno, form|
    next if id.end_with?('_00000000_0_000_0')

    if form_cosmetic?(db, id, gno)
      skipped_cosmetic += 1
      next
    end

    fr = fetch_form_region(db, id)
    if fr.nil?
      skipped_no_stats += 1
      next
    end
    lp_form, lp_region = fr

    base_name = db.get_first_value(<<~SQL, [gno, lang])
      SELECT name FROM pokedex_name
       WHERE globalNo = ? AND language = ?
         AND COALESCE(form, '')           = ''
         AND COALESCE(region, '')         = ''
         AND COALESCE(mega_evolution, '') = ''
         AND COALESCE(gigantamax, '')     = ''
       LIMIT 1
    SQL
    if base_name.nil? || base_name.empty?
      skipped_no_base += 1
      next
    end

    stripped = form.dup
    stripped.sub!(/のすがた\z/, '')
    stripped.sub!(/フォルム\z/, '')
    stripped.sub!(/\s*Forme?\z/i, '')
    stripped.strip!

    alias_name =
      if form.include?(base_name)
        form
      elsif stripped.empty?
        nil
      elsif lang == 'jpn'
        "#{base_name}（#{stripped}）"
      else
        "#{base_name} (#{stripped})"
      end

    if alias_name.nil? || alias_name == base_name
      skipped_same_as_base += 1
      next
    end

    form_col   = lp_region.empty? ? lp_form : nil
    region_col = lp_region.empty? ? nil      : lp_region
    # form も region も空な形態は書き先の列が無い (存在しないはずだが保険)
    next if form_col.to_s.empty? && region_col.to_s.empty?

    existing = db.get_first_value(
      'SELECT COUNT(*) FROM pokedex_name WHERE id = ? AND language = ?',
      [id, lang]
    ).to_i

    if existing > 0
      db.execute(<<~SQL, [alias_name, form_col, region_col, id, lang])
        UPDATE pokedex_name
           SET name = ?, form = ?, region = ?
         WHERE id = ? AND language = ?
      SQL
      updated += 1
    else
      db.execute(<<~SQL, [id, gno, form_col, region_col, lang, alias_name])
        INSERT INTO pokedex_name
          (id, globalNo, form, region, mega_evolution, gigantamax, language, name)
        VALUES (?, ?, ?, ?, NULL, NULL, ?, ?)
      SQL
      inserted += 1
    end
  end
end

puts "    Form-name aliases: #{inserted} inserted, #{updated} updated"
puts "    Skipped: #{skipped_cosmetic} cosmetic, #{skipped_no_base} no base, " \
     "#{skipped_no_stats} no stats, #{skipped_same_as_base} same-as-base"
