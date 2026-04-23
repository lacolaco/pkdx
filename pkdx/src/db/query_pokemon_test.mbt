// query_pokemon に対する integration テスト。
//
// 本来ユニットテストは DB に依存しないほうがいいが、ここで守りたいのは
// 「MoonBit ネイティブの ResultSet が external_object 化されていて、
//   decref が隣接する String バッファを壊さないこと」という FFI レベルの不変条件で、
// これはクエリ結果を実際に取り出してフィールドを検証しないと再現できない。
// そのため setup.sh 済みの `pokedex/pokedex.db` を直接 open する。
//
// CI など DB が無い環境では open に失敗した時点でテスト自体を skip 扱いにする
// （`fail` ではなく `return` することで moon test の pass カウントに影響させる）。
// 通常の開発環境（setup.sh 実行済み）では必ず走る。

///|
/// 開発環境で pokedex.db に到達するパスを返す。moon test の CWD は
/// 実行ごとに異なり得るので候補を順に試す。POKEDEX_DB 環境変数が設定
/// されていればそれを最優先する。
fn find_test_db() -> String? {
  match @sys.get_env_var("POKEDEX_DB") {
    Some(p) => return Some(p)
    None => ()
  }
  let candidates = [
    "pokedex/pokedex.db",
    "../pokedex/pokedex.db",
    "../../pokedex/pokedex.db",
    "../../../pokedex/pokedex.db",
    "../../../../pokedex/pokedex.db",
  ]
  for i = 0; i < candidates.length(); i = i + 1 {
    let path = candidates[i]
    match open(path) {
      Ok(db) => {
        close(db)
        return Some(path)
      }
      Err(_) => continue
    }
  }
  None
}

///|
/// 以前の `(rs - 8)` 書き込みバグでは、legendsza の カイリュー で
/// HP が 91 → 81、type1 が ひこう → ぱこう に破壊されていた。
/// external_object 化した後はすべて正しい値が返る。
test "query_pokemon: カイリュー legendsza (rc-bug regression)" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_pokemon(db, "カイリュー", "legendsza")
  close(db)
  match result {
    Ok(p) => {
      // HP が 91 のままであること（バグ時は 81 になっていた）
      inspect(p.hp, content="91")
      // type1 が ひこう のままであること（バグ時は ぱこう / ばこう などに化けていた）
      inspect(p.type1, content="ひこう")
      inspect(p.type2, content="ドラゴン")
      inspect(p.name_ja, content="カイリュー")
      inspect(p.global_no, content="0149")
    }
    Err(e) => fail("query_pokemon failed: " + e)
  }
}

///|
/// scarlet_violet 側でも同じ不変条件を確認（版依存で回帰しないこと）。
test "query_pokemon: リザードン scarlet_violet" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_pokemon(db, "リザードン", "scarlet_violet")
  close(db)
  match result {
    Ok(p) => {
      inspect(p.hp, content="78")
      inspect(p.type1, content="ほのお")
      inspect(p.type2, content="ひこう")
      inspect(p.name_ja, content="リザードン")
    }
    Err(e) => fail("query_pokemon failed: " + e)
  }
}

///|
/// 複数の数値フィールドをすべて検証する。バグは先頭 codeunit の -1 という
/// 値依存で起きるので、フィールドによって壊れる/壊れないが変わる。数値を
/// 網羅的に assert しておく。
///|
/// champions (デフォルトversion) でメガポケモンが正しくクエリできること。
test "query_pokemon: メガピクシー champions" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_pokemon(db, "メガピクシー", "champions")
  close(db)
  match result {
    Ok(p) => {
      inspect(p.hp, content="95")
      inspect(p.atk, content="80")
      inspect(p.def_, content="93")
      inspect(p.spa, content="135")
      inspect(p.spd, content="110")
      inspect(p.spe, content="70")
      inspect(p.bst, content="583")
      inspect(p.type1, content="フェアリー")
      inspect(p.type2, content="ひこう")
      inspect(p.name_ja, content="メガピクシー")
      inspect(p.global_no, content="0036")
    }
    Err(e) => fail("query_pokemon failed: " + e)
  }
}

///|
/// champions で通常ポケモンのクエリとステータスが正しいこと。
test "query_pokemon: ガブリアス champions stats" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_pokemon(db, "ガブリアス", "champions")
  close(db)
  match result {
    Ok(p) => {
      inspect(p.hp, content="108")
      inspect(p.atk, content="130")
      inspect(p.def_, content="95")
      inspect(p.spa, content="80")
      inspect(p.spd, content="85")
      inspect(p.spe, content="102")
      inspect(p.type1, content="ドラゴン")
      inspect(p.type2, content="じめん")
    }
    Err(e) => fail("query_pokemon failed: " + e)
  }
}

///|
/// champions で技クエリが正しく動作すること。
test "query_moves: ガブリアス champions" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_moves(db, "0445", "champions")
  close(db)
  match result {
    Ok(moves) => {
      // ガブリアスは champions で97技を覚える
      assert_true(moves.length() > 0)
      // じしんが含まれていること
      let mut found_eq = false
      for i = 0; i < moves.length(); i = i + 1 {
        if moves[i].name == "じしん" {
          found_eq = true
          inspect(moves[i].type_, content="じめん")
        }
      }
      assert_true(found_eq)
    }
    Err(e) => fail("query_moves failed: " + e)
  }
}

///|
/// yakkun番号とglobalNoが異なるGen9ポケモンが正しいglobalNoで登録されていること。
test "query_pokemon: スコヴィラン champions globalNo" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_pokemon(db, "スコヴィラン", "champions")
  close(db)
  match result {
    Ok(p) => {
      // yakkun n939 だが正しい globalNo は 0952
      inspect(p.global_no, content="0952")
      inspect(p.name_ja, content="スコヴィラン")
    }
    Err(e) => fail("query_pokemon failed: " + e)
  }
}

///|
test "query_pokemon: ガブリアス scarlet_violet stats" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_pokemon(db, "ガブリアス", "scarlet_violet")
  close(db)
  match result {
    Ok(p) => {
      inspect(p.hp, content="108")
      inspect(p.atk, content="130")
      inspect(p.def_, content="95")
      inspect(p.spa, content="80")
      inspect(p.spd, content="85")
      inspect(p.spe, content="102")
      inspect(p.bst, content="600")
      inspect(p.type1, content="じめん")
      inspect(p.type2, content="ドラゴン")
    }
    Err(e) => fail("query_pokemon failed: " + e)
  }
}

// 008_form_name_aliases (フォーム別名解決) の回帰テスト群。
// 原種→forms[]→特化名 という発見フローが壊れないように検証する。

///|
/// Rotom 系は pokedex_form.form が原種名を含む (ウォッシュロトム ⊃ ロトム)
/// ため、合成せず verbatim で検索できる。フォーム直引きなので forms は空。
test "query_pokemon: ウォッシュロトム champions (direct form alias)" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_pokemon(db, "ウォッシュロトム", "champions")
  close(db)
  match result {
    Ok(p) => {
      inspect(p.global_no, content="0479")
      inspect(p.name_ja, content="ウォッシュロトム")
      // pne 自己結合が form/region で一致するため英語も form 特化になる
      inspect(p.name_en, content="Wash Rotom")
      inspect(p.type1, content="でんき")
      inspect(p.type2, content="みず")
      inspect(p.spa, content="105")
      // フォーム直引きは forms[] 非表示 (原種に戻ってから見る導線)
      inspect(p.forms.length(), content="0")
    }
    Err(e) => fail("query_pokemon failed: " + e)
  }
}

///|
/// アローラのすがた 等のリージョンフォームは species 共有なので
/// "{species}（{form}）" に合成して一意化している。
test "query_pokemon: キュウコン（アローラ） scarlet_violet (composed alias)" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_pokemon(db, "キュウコン（アローラ）", "scarlet_violet")
  close(db)
  match result {
    Ok(p) => {
      inspect(p.global_no, content="0038")
      inspect(p.name_ja, content="キュウコン（アローラ）")
      inspect(p.name_en, content="Ninetales (Alolan)")
      inspect(p.type1, content="こおり")
      inspect(p.atk, content="67")
      inspect(p.forms.length(), content="0")
    }
    Err(e) => fail("query_pokemon failed: " + e)
  }
}

///|
/// 原種 (base) 引きでは forms[] に該当 version に実在するフォームが列挙される。
/// Discoverability の核: ユーザーがここから候補を選んで再 query する。
test "query_pokemon: ロトム champions + forms list (discoverability)" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_pokemon(db, "ロトム", "champions")
  close(db)
  match result {
    Ok(p) => {
      // 原種は base 情報を返す (既存動作の回帰チェックも兼ねる)
      inspect(p.name_ja, content="ロトム")
      inspect(p.type2, content="ゴースト")
      // forms: Rotom appliance 5 形態が全て含まれる
      let mut found_wash = false
      let mut found_heat = false
      let mut found_frost = false
      let mut found_fan = false
      let mut found_mow = false
      for i = 0; i < p.forms.length(); i = i + 1 {
        match p.forms[i] {
          "ウォッシュロトム" => found_wash = true
          "ヒートロトム" => found_heat = true
          "フロストロトム" => found_frost = true
          "スピンロトム" => found_fan = true
          "カットロトム" => found_mow = true
          _ => ()
        }
      }
      assert_true(found_wash)
      assert_true(found_heat)
      assert_true(found_frost)
      assert_true(found_fan)
      assert_true(found_mow)
    }
    Err(e) => fail("query_pokemon failed: " + e)
  }
}

///|
/// 原種引きで合成 alias が forms[] に一意名で現れる。
test "query_pokemon: キュウコン scarlet_violet + forms list (regional)" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_pokemon(db, "キュウコン", "scarlet_violet")
  close(db)
  match result {
    Ok(p) => {
      inspect(p.name_ja, content="キュウコン")
      let mut found = false
      for i = 0; i < p.forms.length(); i = i + 1 {
        if p.forms[i] == "キュウコン（アローラ）" {
          found = true
        }
      }
      assert_true(found)
    }
    Err(e) => fail("query_pokemon failed: " + e)
  }
}

///|
/// 戦闘面で差異のないフォーム (トリミアン毛型・ビビヨン模様) は migration で
/// 除外されるので forms[] に列挙されない (ノイズ防止)。
test "query_pokemon: トリミアン champions (cosmetic forms excluded)" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_pokemon(db, "トリミアン", "champions")
  close(db)
  match result {
    Ok(p) => {
      inspect(p.global_no, content="0676")
      inspect(p.name_ja, content="トリミアン")
      // 10 種類の毛型があるが battle 面で同一なので全て skip
      inspect(p.forms.length(), content="0")
    }
    Err(e) => fail("query_pokemon failed: " + e)
  }
}

///|
/// 単独形態 (フォーム違いなし) のポケモンでは forms[] は空。
test "query_pokemon: ガブリアス scarlet_violet forms empty (no variants)" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_pokemon(db, "ガブリアス", "scarlet_violet")
  close(db)
  match result {
    Ok(p) => {
      // SV ではメガ無し → forms 空
      inspect(p.forms.length(), content="0")
    }
    Err(e) => fail("query_pokemon failed: " + e)
  }
}

///|
/// 存在しない version で form を引いた場合は "Pokemon not found"。
/// Therian Landorus は BW/BW2/LegendsArceus にしか無い。
test "query_pokemon: Therian form absent in SV errors cleanly" {
  let db_path = match find_test_db() {
    Some(p) => p
    None => return
  }
  let db = match open(db_path) {
    Ok(d) => d
    Err(e) => fail("failed to open test db: " + e)
  }
  let result = query_pokemon(
    db, "ランドロス（れいじゅう）", "scarlet_violet",
  )
  close(db)
  match result {
    Ok(_) => fail("should have failed: therian not in SV")
    Err(_) => ()
  }
}
