-- 開発者の画面に管理者パスワードをかける
--
-- ・管理者パスワードは合言葉とは別。ハッシュにして demo.admin_secret に保存する(API からは見えない)
-- ・開発者の画面の関数(件数・サンプルデータにもどす・変更の履歴)は、合言葉と管理者パスワードの両方を確かめる
-- ・パスワードそのものはファイルに残さず、SQL Editor で次を実行して登録する(変えるときも同じ)
--
--     insert into demo.admin_secret (id, passcode_hash)
--     values (1, extensions.crypt('ここに管理者パスワード', extensions.gen_salt('bf')))
--     on conflict (id) do update set passcode_hash = excluded.passcode_hash;

create table if not exists demo.admin_secret (
  id            integer primary key default 1 check (id = 1),
  passcode_hash text not null,
  updated_at    timestamptz not null default now()
);
revoke all on table demo.admin_secret from public, anon, authenticated;

-- 合言葉と管理者パスワードを確かめる
create or replace function public.check_admin(input_passcode text, input_admin text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  h text;
begin
  perform public.check_passcode(input_passcode);
  select s.passcode_hash into h from demo.admin_secret s where s.id = 1;
  if h is null then
    raise exception '管理者パスワードがまだ設定されていません';
  end if;
  if coalesce(input_admin, '') = '' or h <> extensions.crypt(input_admin, h) then
    raise exception '管理者パスワードが違います';
  end if;
  return true;
end;
$$;
revoke all on function public.check_admin(text, text) from public, anon, authenticated;
grant execute on function public.check_admin(text, text) to anon;

-- 引数が変わるので、古い関数は名前を変えて使わない
alter function public.get_demo_info(text) rename to get_demo_info_unused_20261118;
revoke all on function public.get_demo_info_unused_20261118(text) from public, anon, authenticated;
alter function public.reset_demo_data(text) rename to reset_demo_data_unused_20261118;
revoke all on function public.reset_demo_data_unused_20261118(text) from public, anon, authenticated;
alter function public.get_change_log(text, integer) rename to get_change_log_unused_20261118;
revoke all on function public.get_change_log_unused_20261118(text, integer) from public, anon, authenticated;

create or replace function public.reset_demo_data(input_passcode text, input_admin text)
returns jsonb
language plpgsql
security definer
set search_path = ''
set statement_timeout = '60s'
as $$
begin
  perform public.check_admin(input_passcode, input_admin);
  return demo.restore_and_count('button');
end;
$$;
revoke all on function public.reset_demo_data(text, text) from public, anon, authenticated;
grant execute on function public.reset_demo_data(text, text) to anon;

create or replace function public.get_demo_info(input_passcode text, input_admin text)
returns table (table_name text, saved_count integer, restored_count bigint, current_count bigint,
               saved_at timestamptz, restored_at timestamptz, restored_by text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  t text;
  rc jsonb;
begin
  perform public.check_admin(input_passcode, input_admin);
  select m.restored_at, m.restored_by, m.restored_counts into restored_at, restored_by, rc from demo.meta m where m.id = 1;
  foreach t in array demo.tables() loop
    table_name := t;
    saved_count := null;
    saved_at := null;
    select s.row_count, s.saved_at into saved_count, saved_at from demo.snapshots s where s.table_name = t;
    restored_count := (rc ->> t)::bigint;
    execute format('select count(*) from public.%I', t) into current_count;
    return next;
  end loop;
end;
$$;
revoke all on function public.get_demo_info(text, text) from public, anon, authenticated;
grant execute on function public.get_demo_info(text, text) to anon;

create or replace function public.get_change_log(input_passcode text, input_admin text, p_limit integer default 200)
returns table (at timestamptz, actor text, device text, table_name text, op text, summary text)
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_admin(input_passcode, input_admin);
  return query
    select c.at, c.actor, c.device, c.table_name, c.op, c.summary
      from demo.change_log c
     order by c.at desc, c.id desc
     limit least(greatest(coalesce(p_limit, 200), 1), 1000);
end;
$$;
revoke all on function public.get_change_log(text, text, integer) from public, anon, authenticated;
grant execute on function public.get_change_log(text, text, integer) to anon;
