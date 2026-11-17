-- 変更の履歴(開発者の画面に出す)
--
-- ・画面から追加・変更・取消したものを demo.change_log に 1 行ずつ残す(対象は demo.tables() のテーブル)
-- ・誰が変えたかは、ブラウザが付けるヘッダーで見分ける(js/common.js)
--     x-gh-actor:  dev = 開発者の画面で「この端末は自分」にしたブラウザ / それ以外は guest(ポートフォリオを見た人)
--     x-gh-device: ブラウザごとの短い記号(同じ人の操作かどうかがわかる)
--   合言葉は共通なので、見分けはブラウザの申告による(デモ用の目安)
-- ・画面を通らない変更(SQL Editor・pg_cron)と、サンプルデータにもどすときの入れ直しは残さない
-- ・サンプルデータにもどしたことは 1 行で残す(ボタン = dev / guest、自動 = auto)

create table if not exists demo.change_log (
  id         bigint generated always as identity primary key,
  at         timestamptz not null default now(),
  actor      text not null,          -- dev / guest / auto
  device     text,
  table_name text not null,          -- _restore はサンプルデータにもどしたとき
  op         text not null,          -- 追加 / 変更 / 取消 / やめる / もどす
  summary    text
);
create index if not exists change_log_at_idx on demo.change_log (at desc);
revoke all on table demo.change_log from public, anon, authenticated;

-- 画面から呼ばれたときのヘッダー(画面を通らないときは null)
create or replace function demo.request_headers()
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
begin
  return nullif(current_setting('request.headers', true), '')::jsonb;
exception when others then
  return null;
end;
$$;
revoke all on function demo.request_headers() from public, anon, authenticated;

-- 1 行の内容を短い文にする(施設・利用者さん/スタッフ・日付・時刻・内容・コメント)
create or replace function demo.summarize(t text, r jsonb)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  parts text[] := '{}';
  v text;
  d text;
begin
  if r ? 'house_id' and t <> 'staff' then
    select coalesce(nullif(h.short_name, ''), h.name) into v from public.houses h where h.id = (r ->> 'house_id')::uuid;
    parts := parts || v;
  end if;
  if r ? 'resident_id' then
    select x.name || 'さん' into v from public.residents x where x.id = (r ->> 'resident_id')::uuid;
    parts := parts || v;
  end if;
  if r ? 'staff_id' then
    select x.name into v from public.staff x where x.id = (r ->> 'staff_id')::uuid;
    parts := parts || v;
  end if;
  if r ? 'item_id' then
    select x.name into v from public.supply_items x where x.id = (r ->> 'item_id')::uuid;
    parts := parts || v;
  end if;
  if r ? 'room_id' then
    select x.name into v from public.rooms x where x.id = (r ->> 'room_id')::uuid;
    parts := parts || v;
  end if;
  if t in ('residents', 'staff', 'houses', 'supply_items', 'shift_types', 'rooms') then
    parts := parts || (r ->> 'name');
  end if;

  d := coalesce(r ->> 'record_date', r ->> 'work_date', r ->> 'meal_date', r ->> 'measured_date');
  if t = 'room_assignments' then d := r ->> 'move_in_date'; end if;
  if d is not null then parts := parts || to_char(d::date, 'FMMM/FMDD'); end if;

  if t = 'shifts' then
    parts := parts || (left(r ->> 'start_time', 5) || '〜' || left(r ->> 'end_time', 5));
  else
    parts := parts || left(coalesce(r ->> 'record_time', r ->> 'measured_time', r ->> 'routine_time'), 5);
  end if;

  parts := parts || case t
    when 'daily_records' then r ->> 'kind'
    when 'resident_routines' then r ->> 'content'
    when 'meal_plans' then
      (case r ->> 'meal' when 'breakfast' then '朝食' when 'lunch' then '昼食' when 'dinner' then '夕食' else r ->> 'meal' end)
      || (case r ->> 'will_eat' when 'true' then ' ○' when 'false' then ' ×' else '' end)
    when 'resident_medications' then
      (case r ->> 'timing' when 'morning' then '朝' when 'noon' then '昼' when 'evening' then '夕' when 'bedtime' then '寝る前' else r ->> 'timing' end)
      || 'のお薬 ' || coalesce((select string_agg(x, '・') from jsonb_array_elements_text(r -> 'medicines') x), 'なし')
    when 'resident_med_settings' then case r ->> 'empty_check' when 'true' then '空包確認あり' else '空包確認なし' end
    when 'vitals' then concat_ws(' ',
      (r ->> 'temperature') || '℃',
      (r ->> 'bp_high') || '/' || (r ->> 'bp_low'),
      '脈 ' || (r ->> 'pulse'))
    when 'supply_requests' then
      (case r ->> 'status' when 'requested' then '発注' when 'ordered' then '手配済み' when 'delivered' then '届けた' else r ->> 'status' end)
      || ' ' || (r ->> 'quantity') || ' 個'
    when 'supply_stocks' then '在庫 ' || (r ->> 'quantity')
    when 'supply_usages' then '使った'
    when 'room_assignments' then case when r ->> 'move_out_date' is not null then '〜' || to_char((r ->> 'move_out_date')::date, 'FMMM/FMDD') end
    else null
  end;

  if nullif(r ->> 'note', '') is not null then
    parts := parts || ('「' || left(r ->> 'note', 30) || case when length(r ->> 'note') > 30 then '…' else '' end || '」');
  end if;

  return array_to_string(parts, ' ');
end;
$$;
revoke all on function demo.summarize(text, jsonb) from public, anon, authenticated;

-- トリガー: 画面から変えたものだけ残す
create or replace function demo.log_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  h jsonb;
  n jsonb;
  o jsonb;
  op text;
begin
  if coalesce(current_setting('demo.restoring', true), '') = 'on' then return null; end if;
  h := demo.request_headers();
  if h is null then return null; end if;

  n := to_jsonb(new);
  if tg_op = 'UPDATE' then
    o := to_jsonb(old);
    if (n - 'updated_at') = (o - 'updated_at') then return null; end if;
    if n ->> 'voided_at' is not null and o ->> 'voided_at' is null then op := '取消';
    elsif n ->> 'is_active' = 'false' and o ->> 'is_active' = 'true' then op := 'やめる';
    elsif n ->> 'is_active' = 'true' and o ->> 'is_active' = 'false' then op := 'もどす';
    else op := '変更';
    end if;
  else
    op := '追加';
  end if;

  insert into demo.change_log (actor, device, table_name, op, summary)
  values (case when h ->> 'x-gh-actor' = 'dev' then 'dev' else 'guest' end,
          left(h ->> 'x-gh-device', 8), tg_table_name, op, demo.summarize(tg_table_name, n));
  return null;
end;
$$;
revoke all on function demo.log_change() from public, anon, authenticated;

do $$
declare
  t text;
begin
  foreach t in array demo.tables() loop
    execute format(
      'create or replace trigger zz_change_log after insert or update on public.%I for each row execute function demo.log_change()', t);
  end loop;
end;
$$;

-- もどすときは入れ直しを履歴に残さず、もどしたことを 1 行で残す
create or replace function demo.restore_and_count(p_by text default 'cron')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r jsonb;
  t text;
  n bigint;
  h jsonb := demo.request_headers();
  counts jsonb := '{}'::jsonb;
begin
  perform set_config('demo.restoring', 'on', true);
  r := demo.restore(p_by);
  perform set_config('demo.restoring', 'off', true);
  foreach t in array demo.tables() loop
    execute format('select count(*) from public.%I', t) into n;
    counts := counts || jsonb_build_object(t, n);
  end loop;
  update demo.meta set restored_counts = counts where id = 1;
  insert into demo.change_log (actor, device, table_name, op, summary)
  values (case when h is null then 'auto' when h ->> 'x-gh-actor' = 'dev' then 'dev' else 'guest' end,
          left(h ->> 'x-gh-device', 8), '_restore', 'もどす',
          case when h is null then '毎日の自動でサンプルデータにもどした' else 'ボタンでサンプルデータにもどした' end);
  return counts || jsonb_build_object('_shift_days', r -> '_shift_days', '_filled_days', r -> '_filled_days');
end;
$$;
revoke all on function demo.restore_and_count(text) from public, anon, authenticated;

-- 開発者の画面: 新しい順に p_limit 件
create or replace function public.get_change_log(input_passcode text, p_limit integer default 200)
returns table (at timestamptz, actor text, device text, table_name text, op text, summary text)
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_passcode(input_passcode);
  return query
    select c.at, c.actor, c.device, c.table_name, c.op, c.summary
      from demo.change_log c
     order by c.at desc, c.id desc
     limit least(greatest(coalesce(p_limit, 200), 1), 1000);
end;
$$;
revoke all on function public.get_change_log(text, integer) from public, anon, authenticated;
grant execute on function public.get_change_log(text, integer) to anon;
