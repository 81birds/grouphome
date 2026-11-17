-- ポートフォリオ用: ダミーデータの保存と「ダミーデータにもどす」
--
-- ・demo.snapshots に、いまのデータ(ダミーデータ)をテーブルごとに jsonb で保存する
-- ・demo.meta.base_date は、ダミーデータの「今日」(記録はその前日まで入っている)
-- ・もどすときは、日付を 7 の倍数の日数だけずらして、いつも今日の前後にデータがあるようにする
--   (7 の倍数なので曜日は変わらない。土日の昼食・平日の通所・勤務表がくずれない)
--   ずらしきれない 0〜6 日(base_date から今日の前日まで)は、日々の記録とバイタルを 1 週間前の分から写して埋める
-- ・毎日 3:00(日本時間)に pg_cron で自動でもどす。開発者用の画面(dev.html)のボタンでもすぐもどせる
-- ・合言葉(app_secret)は保存も復元もしない
-- ・demo スキーマは API から見えない(anon・authenticated には権限を付けない)
-- ・ダミーデータを作り直したときは、SQL Editor で  select * from demo.save_snapshot();  を実行して保存し直す
--   (画面からは保存できない。見に来た人がダミーデータを書きかえないように)
-- ・新しいテーブルを足したときは、下の demo.tables() に足す(親テーブルが先)

create schema if not exists demo;
revoke all on schema demo from public, anon, authenticated;

create table if not exists demo.snapshots (
  table_name text primary key,
  rows       jsonb not null,
  row_count  integer not null,
  saved_at   timestamptz not null default now()
);
revoke all on table demo.snapshots from public, anon, authenticated;

create table if not exists demo.meta (
  id          integer primary key default 1 check (id = 1),
  base_date   date not null,
  restored_at timestamptz,
  restored_by text
);
revoke all on table demo.meta from public, anon, authenticated;

-- 対象のテーブル(親が先。消すときは逆の順)
create or replace function demo.tables()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array[
    'houses', 'residents', 'shift_types', 'supply_items',
    'staff', 'rooms',
    'shifts', 'room_assignments',
    'daily_records', 'meal_plans', 'vitals', 'resident_routines',
    'resident_medications', 'resident_med_settings',
    'supply_requests', 'supply_stocks', 'supply_usages'
  ]::text[];
$$;
revoke all on function demo.tables() from public, anon, authenticated;

-- 日本の今日
create or replace function demo.today()
returns date
language sql
stable
set search_path = ''
as $$
  select (now() at time zone 'Asia/Tokyo')::date;
$$;
revoke all on function demo.today() from public, anon, authenticated;

-- いまのデータを保存する(SQL Editor から実行する)
--   p_base_date: ダミーデータの「今日」。省略すると、日々の記録の最後の日の翌日
create or replace function demo.save_snapshot(p_base_date date default null)
returns table (table_name text, row_count integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  t text;
  j jsonb;
  b date;
begin
  b := coalesce(p_base_date,
    (select max(r.record_date) + 1 from public.daily_records r where r.voided_at is null),
    demo.today());
  foreach t in array demo.tables() loop
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb) from public.%I x', t) into j;
    insert into demo.snapshots as s (table_name, rows, row_count, saved_at)
    values (t, j, jsonb_array_length(j), now())
    on conflict on constraint snapshots_pkey
      do update set rows = excluded.rows, row_count = excluded.row_count, saved_at = excluded.saved_at;
  end loop;
  insert into demo.meta as m (id, base_date) values (1, b)
  on conflict on constraint meta_pkey do update set base_date = excluded.base_date;
  return query select s.table_name, s.row_count from demo.snapshots s order by array_position(demo.tables(), s.table_name);
end;
$$;
revoke all on function demo.save_snapshot(date) from public, anon, authenticated;

-- 列の一覧(式つき)。p_days 日ずらす: date は + 日数、timestamptz は + 日数の interval
--   p_src: 元の行の別名。p_skip_id: id を除く(写すときは新しい id にする)
create or replace function demo.shifted_cols(p_table text, p_days integer, p_src text, p_keys jsonb, p_skip_id boolean)
returns table (cols text, exprs text)
language sql
stable
set search_path = ''
as $$
  select
    string_agg(format('%I', c.column_name), ', ' order by c.ordinal_position),
    string_agg(
      case
        when c.data_type = 'date' then format('%s.%I + %s', p_src, c.column_name, p_days)
        when c.data_type like 'timestamp%' then format('%s.%I + make_interval(days => %s)', p_src, c.column_name, p_days)
        else format('%s.%I', p_src, c.column_name)
      end, ', ' order by c.ordinal_position)
  from information_schema.columns c
  where c.table_schema = 'public' and c.table_name = p_table
    and c.is_generated = 'NEVER'
    and (p_keys is null or p_keys ? c.column_name)
    and not (p_skip_id and c.column_name = 'id');
$$;
revoke all on function demo.shifted_cols(text, integer, text, jsonb, boolean) from public, anon, authenticated;

-- 保存したダミーデータにもどす(本体。pg_cron とボタンの両方から呼ぶ)
--   いまのデータをすべて消して、保存したデータを日付をずらして入れ直す(デモ用なので、ここだけは物理削除)
--   列はいまのテーブルと保存したデータの両方にあるものだけ入れる(あとで足した列は既定値になる)
create or replace function demo.restore(p_by text default 'cron')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  tbls text[] := demo.tables();
  t text;
  i integer;
  base date;
  today date := demo.today();
  off integer;
  gap integer;
  c record;
  snap jsonb;
  n integer;
  result jsonb := '{}'::jsonb;
begin
  select m.base_date into base from demo.meta m where m.id = 1;
  if base is null or (select count(*) from demo.snapshots) = 0 then
    raise exception 'ダミーデータが保存されていません';
  end if;

  -- ずらす日数(7 の倍数。今日より先にはずらさない)と、埋める日数
  off := greatest(0, ((today - base) / 7) * 7);
  gap := least(6, greatest(0, today - base - off));

  -- 子のテーブルから消す
  for i in reverse array_length(tbls, 1) .. 1 loop
    execute format('delete from public.%I where true', tbls[i]);
  end loop;

  -- 親のテーブルから、日付をずらして入れる
  foreach t in array tbls loop
    select s.rows into snap from demo.snapshots s where s.table_name = t;
    if snap is null or jsonb_array_length(snap) = 0 then
      result := result || jsonb_build_object(t, 0);
      continue;
    end if;
    select * into c from demo.shifted_cols(t, off, 'x', snap -> 0, false);
    execute format(
      'insert into public.%I (%s) select %s from jsonb_populate_recordset(null::public.%I, $1) x',
      t, c.cols, c.exprs, t) using snap;
    get diagnostics n = row_count;
    result := result || jsonb_build_object(t, n);
  end loop;

  -- ずらしきれなかった日(base + off 〜 今日の前日)を、1 週間前の記録で埋める
  if gap > 0 then
    select * into c from demo.shifted_cols('daily_records', 7, 'x', null, true);
    execute format(
      'insert into public.daily_records (%s) select %s from public.daily_records x
        where x.voided_at is null and x.record_date >= $1 and x.record_date < $2',
      c.cols, c.exprs) using base + off - 7, base + off - 7 + gap;
    select * into c from demo.shifted_cols('vitals', 7, 'x', null, true);
    execute format(
      'insert into public.vitals (%s) select %s from public.vitals x
        where x.voided_at is null and x.measured_date >= $1 and x.measured_date < $2',
      c.cols, c.exprs) using base + off - 7, base + off - 7 + gap;
  end if;

  update demo.meta set restored_at = now(), restored_by = p_by where id = 1;
  return result || jsonb_build_object('_shift_days', off, '_filled_days', gap);
end;
$$;
revoke all on function demo.restore(text) from public, anon, authenticated;

-- 画面の「ダミーデータにもどす」
create or replace function public.reset_demo_data(input_passcode text)
returns jsonb
language plpgsql
security definer
set search_path = ''
set statement_timeout = '60s'
as $$
begin
  perform public.check_passcode(input_passcode);
  return demo.restore('button');
end;
$$;
revoke all on function public.reset_demo_data(text) from public, anon, authenticated;
grant execute on function public.reset_demo_data(text) to anon;

-- 開発者用の画面に出す: 保存したダミーデータといまのデータの件数、最後にもどした日時
create or replace function public.get_demo_info(input_passcode text)
returns table (table_name text, saved_count integer, current_count bigint, saved_at timestamptz, restored_at timestamptz, restored_by text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  t text;
begin
  perform public.check_passcode(input_passcode);
  select m.restored_at, m.restored_by into restored_at, restored_by from demo.meta m where m.id = 1;
  foreach t in array demo.tables() loop
    table_name := t;
    saved_count := null;
    saved_at := null;
    select s.row_count, s.saved_at into saved_count, saved_at from demo.snapshots s where s.table_name = t;
    execute format('select count(*) from public.%I', t) into current_count;
    return next;
  end loop;
end;
$$;
revoke all on function public.get_demo_info(text) from public, anon, authenticated;
grant execute on function public.get_demo_info(text) to anon;

-- 毎日 3:00(日本時間 = UTC 18:00)に自動でもどす
create extension if not exists pg_cron;
select cron.schedule('demo-restore-daily', '0 18 * * *', $$select demo.restore('cron')$$);

-- いまのデータを保存する(ダミーデータの「今日」は 2026-11-16。記録は 11/15 まで入っている)
select * from demo.save_snapshot('2026-11-16');
