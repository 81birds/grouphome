# グループホーム アプリ(試作)

グループホームのスタッフ用 Web アプリです。ブラウザだけで動き、データは Supabase に保存されます。

## 画面一覧

最初に合言葉を入力すると、各画面のアイコンが表示されます。

| 画面 | ファイル | できること | 状態 |
|---|---|---|---|
| ログイン | `login.html` | 合言葉の入力 | ✅ |
| ポータル | `index.html` | 各画面へのメニュー | ✅ |
| 利用者 | `residents.html` | 利用者の追加・基本情報の編集・退居の切り替え | ✅ |
| 日々の記録 | — | ケース記録・様子のメモ | 準備中 |
| バイタル | — | 体温・血圧・食事量など | 準備中 |
| 服薬 | — | 服薬チェック | 準備中 |
| 申し送り | — | スタッフ間の連絡 | 準備中 |
| 設定 | — | スタッフ・事業所の編集 | 準備中 |

## はじめての準備

### 1. Supabase

1. Supabase で新しいプロジェクトを作る(リージョンは Tokyo がおすすめ)
2. **SQL Editor** で `sql/2026-10-10_init.sql` を実行する
3. 同じく **SQL Editor** で合言葉を登録する(合言葉はファイルに残さず、ここで直接実行する)

   ```sql
   insert into public.app_secret (id, passcode_hash)
   values (1, extensions.crypt('ここに合言葉', extensions.gen_salt('bf')))
   on conflict (id) do update set passcode_hash = excluded.passcode_hash;
   ```

   合言葉を変えるときも同じ SQL を実行します。各端末で一度ログアウトされます

4. **Project Settings → API Keys** の Project URL と Publishable key を `js/config.js` に書く

### 2. ローカルで確認

VS Code でこのフォルダを開き、`index.html` を右クリック → **Open with Live Server**。

### 3. GitHub と Vercel

1. GitHub に新しいリポジトリ(Private 推奨)を作って push する
2. Vercel で **Add New → Project** からそのリポジトリを選ぶ(Framework Preset は **Other**、ビルド設定は空のまま)
3. 以降は `main` に push するたびに自動でデプロイされます

## しくみ

- **フロントエンド**: ビルド不要の静的 HTML。共通のデザインは `css/common.css`、共通の処理は `js/common.js` にまとめています
- **データベース**: Supabase(PostgreSQL)
  - テーブルへの直接アクセスは許可していません。画面からは `rpc` で関数(`get_residents` など)を呼びます
  - どの関数も最初に `check_passcode` で合言葉を確認します。合言葉はブラウザの localStorage に保存されます

## データベースの変更

- 変更は `sql/YYYY-MM-DD_内容.sql` という名前で追加し、Supabase で実行してからコミットします
- 過去の SQL ファイルは書き換えません

開発のルール(デザイン・画面の追加方法など)は `CLAUDE.md` にまとめています。
