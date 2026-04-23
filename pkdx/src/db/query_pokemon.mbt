///|
/// Query a Pokemon by name (Japanese or English).
pub fn query_pokemon(
  db : Db,
  name : String,
  version : String,
) -> Result[@model.Pokemon, String] {
  // pokedex_name には base 行に加えて、008_form_name_aliases migration で
  // フォーム別の一意な別名 (ウォッシュロトム / キュウコン（アローラ） 等) が
  // 入っている。alias 行は form / region が非空なので、ここでは form / region
  // による絞り込みはしない (絞ると alias に hit できない)。
  // pne 自己結合は form / region / mega_evolution が一致する jpn/eng ペアを
  // 取るよう条件を追加する。
  let sql =
    #|SELECT
    #|  pn.id,
    #|  pn.globalNo,
    #|  pn.name AS name_ja,
    #|  pne.name AS name_en,
    #|  t.type1, t.type2,
    #|  s.hp, s.attack, s.defense, s.special_attack, s.special_defense, s.speed,
    #|  (s.hp + s.attack + s.defense + s.special_attack + s.special_defense + s.speed) AS bst,
    #|  a.ability1, a.ability2, a.dream_ability,
    #|  p.weight
    #|FROM pokedex_name pn
    #|JOIN pokedex_name pne ON pn.id = pne.id
    #|  AND COALESCE(pne.form, '')           = COALESCE(pn.form, '')
    #|  AND COALESCE(pne.region, '')         = COALESCE(pn.region, '')
    #|  AND COALESCE(pne.mega_evolution, '') = COALESCE(pn.mega_evolution, '')
    #|  AND pne.language = 'eng'
    #|JOIN local_pokedex_type t ON pn.id = t.id
    #|  AND COALESCE(t.mega_evolution, '') = COALESCE(pn.mega_evolution, '')
    #|  AND t.version = ?
    #|JOIN local_pokedex_status s ON pn.id = s.id
    #|  AND COALESCE(s.mega_evolution, '') = COALESCE(pn.mega_evolution, '')
    #|  AND s.version = ?
    #|JOIN local_pokedex_ability a ON pn.id = a.id
    #|  AND COALESCE(a.mega_evolution, '') = COALESCE(pn.mega_evolution, '')
    #|  AND a.version = ?
    #|JOIN pokedex p ON pn.id = p.id
    #|WHERE (pn.language = 'jpn' AND pn.name = ?)
    #|   OR (pn.language = 'eng' AND LOWER(pn.name) = LOWER(?))
    #|LIMIT 1
  let rows = match query(db, sql, [version, version, version, name, name]) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  if rows.length() == 0 {
    return Err("Pokemon not found: " + name)
  }
  let r = rows[0]
  let id = r[0]
  let global_no = r[1]

  // 原種 (base id) を引いた時だけ forms[] を埋める (discoverability)。
  // 該当 version に実在するフォームだけに絞るため local_pokedex_status を JOIN。
  let forms : Array[String] = if is_base_id(id) {
    query_forms(db, global_no, id, version)
  } else {
    []
  }

  Ok(@model.Pokemon::{
    global_no,
    name_ja: r[2],
    name_en: r[3],
    type1: r[4],
    type2: r[5],
    hp: parse_int(r[6]),
    atk: parse_int(r[7]),
    def_: parse_int(r[8]),
    spa: parse_int(r[9]),
    spd: parse_int(r[10]),
    spe: parse_int(r[11]),
    bst: parse_int(r[12]),
    ability1: r[13],
    ability2: r[14],
    dream_ability: r[15],
    weight: parse_double(r[16]),
    forms,
  })
}

///|
/// base id (globalNo_00000000_0_000_0) かどうか。
fn is_base_id(id : String) -> Bool {
  // suffix "_00000000_0_000_0" で判定
  let suffix = "_00000000_0_000_0"
  if id.length() < suffix.length() {
    return false
  }
  let start = id.length() - suffix.length()
  for i = 0; i < suffix.length(); i = i + 1 {
    if id[start + i] != suffix[i] {
      return false
    }
  }
  true
}

///|
/// 指定 globalNo の、引いた id 以外で該当 version に存在するフォーム alias を返す。
/// 008_form_name_aliases migration によって各 alias は語彙的に一意 (例:
/// "ウォッシュロトム", "キュウコン（アローラ）") なのでそのまま `pkdx query` の
/// 引数として使える。
fn query_forms(
  db : Db,
  global_no : String,
  self_id : String,
  version : String,
) -> Array[String] {
  let sql =
    #|SELECT DISTINCT pn.name
    #|FROM pokedex_name pn
    #|JOIN local_pokedex_status s ON pn.id = s.id
    #|  AND COALESCE(s.mega_evolution, '') = COALESCE(pn.mega_evolution, '')
    #|  AND s.version = ?
    #|WHERE pn.globalNo = ?
    #|  AND pn.language = 'jpn'
    #|  AND pn.id != ?
    #|ORDER BY pn.id
  match query(db, sql, [version, global_no, self_id]) {
    Ok(rows) => {
      let out : Array[String] = []
      for i = 0; i < rows.length(); i = i + 1 {
        out.push(rows[i][0])
      }
      out
    }
    Err(_) => []
  }
}

///|
/// DBの weight カラムは "460.0" や "-" などの文字列。
/// "-" や解析不能値は 0.0 を返す。
fn parse_double(s : String) -> Double {
  if s.length() == 0 {
    return 0.0
  }
  let mut i = 0
  let mut negative = false
  if s[i] == '-' {
    // 単独の "-" はデータ欠損マーカー
    if s.length() == 1 {
      return 0.0
    }
    negative = true
    i = i + 1
  }
  let mut int_part = 0.0
  while i < s.length() && s[i] != '.' {
    let c = s[i].to_int()
    if c >= 0x30 && c <= 0x39 {
      int_part = int_part * 10.0 + (c - 0x30).to_double()
    }
    i = i + 1
  }
  let mut frac = 0.0
  let mut div = 1.0
  if i < s.length() && s[i] == '.' {
    i = i + 1
    while i < s.length() {
      let c = s[i].to_int()
      if c >= 0x30 && c <= 0x39 {
        frac = frac * 10.0 + (c - 0x30).to_double()
        div = div * 10.0
      }
      i = i + 1
    }
  }
  let result = int_part + frac / div
  if negative {
    -result
  } else {
    result
  }
}

///|
fn parse_int(s : String) -> Int {
  let mut result = 0
  let mut i = 0
  let mut negative = false
  if i < s.length() && s[i] == '-' {
    negative = true
    i = i + 1
  }
  while i < s.length() {
    let c = s[i].to_int()
    if c >= 0x30 && c <= 0x39 {
      result = result * 10 + (c - 0x30)
    }
    i = i + 1
  }
  if negative {
    -result
  } else {
    result
  }
}
