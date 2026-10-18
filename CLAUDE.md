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
residents.html    利用者(一覧と登録をタブで切り替え。施設・部屋を押すと入居・部屋の移動・退居のダイアログ)
staff.html        スタッフ(一覧と登録をタブで切り替え。所属施設はプルダウン)
houses.html       施設(上の施設ボタンで「部屋と入居者」を切り替え)
shifts.html       勤務表。タブで「勤務表(月の表・ダイアログでの入力)」「個人の勤務」「勤務区分」を切り替え
                  個人の勤務は縦=時間・横=施設のチェック表。勤務の入力はここが基本。スマホ向け(?tab=my&staff=&date= で直接開ける)
myshift.html      前のブックマーク用。shifts.html の「個人の勤務」タブへ転送するだけ
records.html      日々の記録(施設→本日のスタッフを表示→利用者→その日の記録→「新しい入力」のダイアログで時刻ホイール・内容チップ・コメント。スマホ向け)
family.html       利用者さんの画面(作成中)。ハウス→名前を選ぶとその人の画面: 本日のスタッフ・本日の予定(まだ空)・食事表(○×)。スマホ向け
meals.html        食数管理。日ごとに、ハウス×食事の ○ の数と、利用者さんごとの ○×
css/common.css    全画面共通のデザイン(色・部品)
js/config.js      アプリ名と Supabase の URL / publishable key
js/common.js      Supabase クライアント、合言葉の確認、上部タブ、共通関数(window.App)
js/rooms.js       部屋と入居の共通処理(window.Rooms)。houses.html・residents.html・records.html・family.html・meals.html で使う
js/staffday.js    本日のスタッフ(その日・その施設の勤務の帯。window.StaffDay)。records.html・family.html で使う
js/meals.js       食事の予定の共通処理(window.Meals)。family.html・meals.html で使う
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
- ダイアログ(`.modal`)は画面の高さに収まり、中だけスクロールする。決定ボタンは `.modal-actions` か `.modal-foot` に入れる(下に固定され、スマホでも画面の外に出ない)。スマホでは下から出るシートになる
- PC では画面を広く使う(`.wrap.wide`。日々の記録は 1000px 以上で 2 列)

## 新しい画面の作り方

1. `staff.html` などの近い画面をコピーして `xxx.html` を作る(head、`#gtoolBar`、`#loadingScreen`、`#mainContent`、スクリプト読み込み順はそのまま)
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
- 個人の勤務(shifts.html の「個人の勤務」タブ)は 1 時間単位のチェックボックス。チェックは画面上だけで変わり、「保存」でまとめて保存する(スマホで軽く動かすため)
- 保存するときは、チェックが変わった施設の勤務だけを作り直す。変えていない端の時刻(9:30 始まりなど)はそのまま残す

## 部屋と入居のルール

- 部屋は `rooms`(施設ごと)。入居 1 件は `room_assignments` の 1 行(resident_id・room_id・move_in_date・move_out_date)
- 期間は [入居日, 退居日)。退居日が空なら入居中。退居日にはその部屋は空いていて、同じ日に次の人が入居できる
- 1 つの部屋に同じ期間 2 人は入れない。同じ利用者が同じ期間に 2 部屋にも入れない(`assign_room` が止める)
- 入居中の人を別の部屋に入居させると、前の部屋はその日で退居になる(部屋の移動)
- 記録は消さない。間違いは `void_room_assignment` で取り消す(voided_at)
- `residents.room` / `residents.move_in_date` は使わない(入居の記録に移った)

## 日々の記録のルール

- 記録 1 件は `daily_records` の 1 行(resident_id・house_id・record_date・record_time・kind)。内容のチップは 1 つだけ選べる(`add_daily_records` は配列で受けるが、画面からは 1 件ずつ)
- 内容の種類は `records.html` の `KINDS` で決める(名前とアイコン)。増やすときは DB の変更はいらない。名前を変えると過去の記録とは別の内容として扱われる
- 利用者のボタンは部屋の数だけ並べる。その日その施設の部屋に入居している人(`Rooms.occupantOf`)を出し、いない部屋は「空室」(押せない)
- `house_id` は記録したときの施設。部屋を移っても過去の記録の施設は変えない
- 入力中も施設と日にちが必ず見えるようにする。施設のカードが上に隠れたら上部に帯(施設・日にち・利用者)を出し、ダイアログにも施設と日にちを出す。オレンジの「〇〇さんの記録を入力中です」は新しい入力のダイアログだけ
- 新しい入力ではコメント(`note`)も一緒に入れられる。記録したあと、時刻と内容は残し、コメントは消す
- 施設を選ぶと、同じカードの中に「本日のスタッフ」(その日その施設の勤務。前日からの夜勤も含む)を出す
- 利用者を選ぶと、その人のその日の記録を出す。「新しい入力」でダイアログを開き、時刻と内容を選んで記録する
- 時刻はスクロール式のホイール(時 0〜23・分は 10 分きざみ。「いま」は 10 分単位に丸める)。記録したあとも時刻と内容は残す(次の利用者にすぐ同じ内容を記録できるように)
- 記録の鉛筆ボタンで編集ダイアログを開き、時刻とコメント(`note`)を直せる(`update_daily_record`)。ホイールを動かさなければ元の時刻(9:37 など)のまま。取消もここから
- 記録は消さない。間違いは `void_daily_record` で取り消す(voided_at)

## 食事の予定のルール

- 1 行は `meal_plans`(resident_id・meal_date・meal・will_eat)。meal は breakfast / lunch / dinner。true = ○ 食べる、false = × 食べない、行なし = 未回答
- 土日は朝・昼・夕の 3 食、平日は朝と夕(平日の昼は `set_meal_plan` が止める)
- 利用者さんの画面で、押すたびに ○ → × → ○ と切り替わり、すぐ保存する
- ハウスは持たない。その日に入居している部屋から決める(食数管理もそうやって数える)

## 個人情報の扱い

- 実在の利用者・スタッフの情報をコード、SQL、コミット、テストデータに書かない。サンプルは架空の名前にする
- `console.log` に利用者の情報を出さない(エラーオブジェクトの出力は可)
- 画面に表示する値は `App.escapeHtml()` を通すか `textContent` で入れる

## 本番運用の前に(試作のあいだは保留)

- 共通の合言葉から、スタッフごとのログイン(Supabase Auth)に切り替える
- 誰が記録したかを残す(記録テーブルに記入者を持たせる)
