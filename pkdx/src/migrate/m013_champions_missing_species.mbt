///|
/// Champions テーブルから抜けている SV 追加種を補う。
///
/// Problem: pokedex submodule が出力する Champions データには一部の SV/DLC
/// 追加種が含まれず、`pkdx query "ヤバソチャ" --version champions` 等が
/// "Pokemon not found" になる。当該種は SV reg と同等のステ/タイプ/特性で
/// Champions M-A にも合法 (yakkun.com Champions 投稿実績あり)。
///
/// 対象 (現状):
///   - 1013 ヤバソチャ (Sinistcha) — Champions の表示は cosmetic form を
///     畳んで base id 1 行のみ (ポットデス 0855 のパターンに揃える)
///
/// 投入: pkdx_patch/013_champions_missing_species/data.json を読み、
/// 各エントリについて local_pokedex / _status / _type / _ability の
/// 該当 (id, version='champions') 行を DELETE してから INSERT する。
/// pokedex / pokedex_name / pokedex_form は SV 行が既に持っているので
/// 触らない (002 の new_pokedex_entry=true パスに相当する処理は不要)。
///
/// Resync 安全性: 投入対象 id だけを DELETE → INSERT するので、002 が
/// 入れた他 Champions 行とは衝突しない。
pub fn run_013(db : @db.Db, repo_root : String) -> Result[String, String] {
  let path = repo_root + "/pkdx_patch/013_champions_missing_species/data.json"
  let raw = match @db.read_file(path) {
    Some(s) => s
    None => return Err(path + " not found.")
  }
  let json = try @json.parse(raw) catch {
    e => return Err("JSON parse: " + e.to_string())
  }
  let entries = match expect_array(json) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  let version = "champions"
  let mut count = 0
  for entry_json in entries {
    let entry = match entry_json {
      Object(m) => m
      _ => return Err("entry is not an object")
    }
    let id = str_field(entry, "id")
    let no = str_field(entry, "no")
    let global_no = str_field(entry, "globalNo")
    let form = bind_text_opt(str_opt(entry, "form"))
    let region = bind_text_opt(str_opt(entry, "region"))
    let mega_evo = bind_text_opt(str_opt(entry, "mega_evolution"))
    let gigantamax = bind_text_opt(str_opt(entry, "gigantamax"))
    let pokedex_s = str_field(entry, "pokedex")
    let cleanup_tables = [
      "local_pokedex",
      "local_pokedex_status",
      "local_pokedex_type",
      "local_pokedex_ability",
    ]
    for t in cleanup_tables {
      match @db.exec_binds(
          db,
          "DELETE FROM " + t + " WHERE id = ? AND version = ?",
          [@db.BindText(id), @db.BindText(version)],
        ) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
    }
    match @db.exec_binds(
        db,
        "INSERT INTO local_pokedex (id, no, globalNo, form, region, mega_evolution, gigantamax, version, pokedex) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
          @db.BindText(id),
          @db.BindText(no),
          @db.BindText(global_no),
          form,
          region,
          mega_evo,
          gigantamax,
          @db.BindText(version),
          @db.BindText(pokedex_s),
        ],
      ) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    match @db.exec_binds(
        db,
        "INSERT INTO local_pokedex_status (id, globalNo, form, region, mega_evolution, gigantamax, version, hp, attack, defense, special_attack, special_defense, speed) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
          @db.BindText(id),
          @db.BindText(global_no),
          form,
          region,
          mega_evo,
          gigantamax,
          @db.BindText(version),
          @db.BindInt(int_field(entry, "hp", 0)),
          @db.BindInt(int_field(entry, "attack", 0)),
          @db.BindInt(int_field(entry, "defense", 0)),
          @db.BindInt(int_field(entry, "special_attack", 0)),
          @db.BindInt(int_field(entry, "special_defense", 0)),
          @db.BindInt(int_field(entry, "speed", 0)),
        ],
      ) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    let type2 = bind_text_opt(str_opt(entry, "type2"))
    match @db.exec_binds(
        db,
        "INSERT INTO local_pokedex_type (id, globalNo, form, region, mega_evolution, gigantamax, version, type1, type2) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
          @db.BindText(id),
          @db.BindText(global_no),
          form,
          region,
          mega_evo,
          gigantamax,
          @db.BindText(version),
          @db.BindText(str_field(entry, "type1")),
          type2,
        ],
      ) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    let ability1 = bind_text_opt(str_opt(entry, "ability1"))
    let ability2 = bind_text_opt(str_opt(entry, "ability2"))
    let dream = bind_text_opt(str_opt(entry, "dream_ability"))
    match @db.exec_binds(
        db,
        "INSERT INTO local_pokedex_ability (id, globalNo, form, region, mega_evolution, gigantamax, version, ability1, ability2, dream_ability) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
          @db.BindText(id),
          @db.BindText(global_no),
          form,
          region,
          mega_evo,
          gigantamax,
          @db.BindText(version),
          ability1,
          ability2,
          dream,
        ],
      ) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    count = count + 1
  }
  Ok(
    "Champions missing species: " + count.to_string() + " species inserted",
  )
}
