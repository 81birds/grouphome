# CLAUDE.md

グループホーム向けのスタッフ用 Web アプリ(試作段階)。介護記録など個人情報・健康情報を扱う。

## 技術スタック

- フロントエンド: ビルド不要の静的 HTML / CSS / JavaScript(フレームワークなし)
- 外部ライブラリは CDN から読み込む: supabase-js v2、Tabler Icons(webfont 2.47.0)、Noto Sans JP
- データベース: Supabase(PostgreSQL)
- ログイン: 共通の合言葉(流通ポータルと同じ方式)。合言葉はハッシュ化して `app_secret` に保存
- 開発時は VS Code の Live Server で確認する
- ホスティング: GitHub の `main` に push → Vercel に自動デプロイ。`vercel.json` の `cleanUrls` で拡張子なしでも開ける

## フォルダ構成

```
index.html        ポータル(アイコンタイルのメニュー)
login.html        合言葉の入力画面
residents.html    利用者(新しい画面を作るときのお手本)
staff.html        スタッフ(所属施設をプルダウンで選ぶ例)
houses.html       施設
shifts.html       勤務表(月の表・ダイアログでの入力・勤務区分タブ)
myshift.html      個人の勤務(縦=時間・横=施設のマスを選んで登録。勤務の入力はここが基本)
css/common.css    全画面共通のデザイン(色・部品)
js/config.js      アプリ名と Supabase の URL / publishable key
js/common.js      Supabase クライアント、合言葉の確認、上部タブ、共通関数(window.App)
sql/              DB の変更履歴(YYYY-MM-DD_内容.sql)
```

## パスとリンク

- CSS・JS・リンクはすべて相対パスで書く(`css/common.css`、`residents.html`)
- `/residents` や `/css/...` のような先頭が `/` のパスは Live Server で開けないので使わない

## デザインのルール

デザインは別プロジェクト「流通ポータル」と同じ。新しい画面も必ず揃える。

- 色・角丸・影は `css/common.css` の CSS 変数(`--color-primary` など)だけを使う。ページに色コードを直接書かない
- 使う部品: `.card`(h2 にアイコン)、`.btn` / `.btn-ghost` / `.btn-danger` / `.btn-sm`、`.tabs` + `.tab-btn`、`.chips`、`.add-row` + `.field`、`.compact-table`、`.status-msg`、`.empty-msg`
- 共通部品で足りないときは `common.css` に追加する。1 画面だけで使うものはその画面の `<style>` に書いてよい
- アイコンは Tabler Icons(`<i class="ti ti-xxx"></i>`)
- 画面の文言はやさしい日本語。スタッフは PC だけでなくスマホ・タブレットでも使うので、幅 360px でも崩れないようにする
- ページ見出しは `.page-header`(`.page-icon` + h1 + 説明の p)

## 新しい画面の作り方

1. `residents.html` をコピーして `xxx.html` を作る(head、`#gtoolBar`、`#loadingScreen`、`#mainContent`、スクリプト読み込み順はそのまま)
2. `js/common.js` の `PAGES` に追加(または `ready: false` を `true` に)。これで上部タブとポータルのタイルの両方に出る
3. ページのスクリプトは `App.boot({ active: 'xxx', onReady: async () => { ... } })` で始める。`onReady` が終わるまで「確認しています...」が表示され、合言葉が未入力・誤りなら自動で `login.html` に移動する
4. DB は `App.rpc('関数名', { p_xxx: ... })` で呼ぶ。合言葉(`input_passcode`)は自動で付く

## データベースのルール(流通ポータルと同じ方式)

- テーブルへの直接アクセスは許可しない。新しいテーブルも RLS を有効にし、`revoke all ... from anon, authenticated` する
- 画面からの読み書きはすべて関数(rpc)経由。関数は次の形で作る
  - 第 1 引数は `input_passcode text`、本文の最初で `perform public.check_passcode(input_passcode);`
  - `security definer` と `set search_path = ''` を付け、テーブル名は `public.xxx` と書く
  - `revoke all on function ... from public, anon, authenticated;` のあと `grant execute ... to anon;`
- 物理削除はせず `is_active` や `voided_at` などで論理削除する
- `updated_at` は共通関数 `public.set_updated_at()` のトリガーで更新する
- 変更は `sql/YYYY-MM-DD_内容.sql` を追加し、Supabase の SQL Editor で実行してからコミットする。過去の SQL ファイルは書き換えない
- Claude がコネクタ(apply_migration)で実行する SQL には、削除の命令(`drop`)を書かない。コメントの中にも書かない。確認画面が出せずキャンセルになるため
  - トリガーは `create or replace trigger` を使う
  - 関数の引数を変えるときは、古い関数を `alter function ... rename to xxx_unused_日付` にして権限を外す
  - どうしても削除が必要なときは、SQL を渡して SQL Editor で実行してもらう
- 合言葉そのもの、service_role / secret key は、コード・SQL ファイル・コミットに絶対に書かない。`config.js` に書くのは publishable key だけ

## 勤務(シフト)のルール

- 勤務 1 件は `shifts` の 1 行(work_date・staff_id・house_id・start_time・end_time)
- `work_date` は勤務が始まる日。`end_time <= start_time` なら翌日に終わる(夜勤 22:00〜翌10:00)
- 時間の重なりは `public.shift_range()` で判定し、同じスタッフの重なる勤務は `save_shift` が保存を拒む
- ある日・ある施設に「誰がいるか」を出すときは、前日に始まった夜勤も含める(`get_shifts` は前日分も返す)
- 同じ時間・同じ施設に複数のスタッフが入るのは正常(配膳スタッフと看護師など)。止めるのは同じスタッフの重なりだけ
- 個人の勤務ページは 1 時間単位で選ぶ。選んだ範囲にかかる勤務だけを作り直し、ほかの勤務(9:30 始まりなど)は触らない

## 個人情報の扱い

- 実在の利用者・スタッフの情報をコード、SQL、コミット、テストデータに書かない。サンプルは架空の名前にする
- `console.log` に利用者の情報を出さない(エラーオブジェクトの出力は可)
- 画面に表示する値は `App.escapeHtml()` を通すか `textContent` で入れる

## 本番運用の前に(試作のあいだは保留)

- 共通の合言葉から、スタッフごとのログイン(Supabase Auth)に切り替える
- 誰が記録したかを残す(記録テーブルに記入者を持たせる)
