-- =====================================================
-- 初期構築: 合言葉と利用者テーブル
-- Supabase ダッシュボード → SQL Editor に貼り付けて実行する
--
-- 方針(流通ポータルと同じ)
--   ・テーブルへの直接アクセスは許可しない(RLS 有効・ポリシーなし・権限なし)
--   ・画面からは rpc で関数を呼ぶ。どの関数も最初に check_passcode で合言葉を確認する
--   ・合言葉はハッシュ化して app_secret に保存する(このファイルには書かない)
--   ・物理削除はせず is_active などで論理的に扱う
-- =====================================================

create extension if not exists pgcrypto with schema extensions;

-- ----- 合言葉 -----
create table if not exists public.app_secret (
  id            integer primary key default 1 check (id = 1),
  passcode_hash text not null
);
alter table public.app_secret enable row level security;
revoke all on public.app_secret from anon, authenticated;

create or replace function public.check_passcode(input_passcode text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  is_valid boolean;
begin
  select (s.passcode_hash = extensions.crypt(input_passcode, s.passcode_hash))
    into is_valid
    from public.app_secret s
   where s.id = 1;

  if is_valid is not true then
    raise exception '合言葉が違います';
  end if;
  return true;
end;
$$;

-- updated_at を自動更新する共通関数(以降のテーブルでも使う)
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ----- 利用者 -----
create table if not exists public.residents (
  id            uuid primary key default gen_random_uuid(),
  name          text not null check (length(trim(name)) > 0),
  kana          text,
  room          text,
  move_in_date  date,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table  public.residents              is '利用者';
comment on column public.residents.name         is '氏名';
comment on column public.residents.kana         is 'ふりがな';
comment on column public.residents.room         is '部屋';
comment on column public.residents.move_in_date is '入居日';
comment on column public.residents.is_active    is '入居中なら true、退居したら false';

drop trigger if exists residents_set_updated_at on public.residents;
create trigger residents_set_updated_at
  before update on public.residents
  for each row execute function public.set_updated_at();

alter table public.residents enable row level security;
revoke all on public.residents from anon, authenticated;

-- ----- 利用者の関数 -----
create or replace function public.get_residents(input_passcode text)
returns setof public.residents
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_passcode(input_passcode);
  return query
    select * from public.residents r
     order by r.room asc nulls last, r.kana asc nulls last, r.created_at;
end;
$$;

create or replace function public.add_resident(
  input_passcode text,
  p_name text,
  p_kana text default null,
  p_room text default null,
  p_move_in_date date default null
)
returns public.residents
language plpgsql
security definer
set search_path = ''
as $$
declare
  row public.residents;
begin
  perform public.check_passcode(input_passcode);
  insert into public.residents (name, kana, room, move_in_date)
  values (trim(p_name), nullif(trim(p_kana), ''), nullif(trim(p_room), ''), p_move_in_date)
  returning * into row;
  return row;
end;
$$;

-- 1 項目だけ更新する(一覧の自動保存用)
create or replace function public.update_resident_field(
  input_passcode text,
  p_id uuid,
  p_field text,
  p_value text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_passcode(input_passcode);
  p_value := nullif(trim(p_value), '');

  if p_field = 'name' then
    if p_value is null then raise exception '氏名は空にできません'; end if;
    update public.residents set name = p_value where id = p_id;
  elsif p_field = 'kana' then
    update public.residents set kana = p_value where id = p_id;
  elsif p_field = 'room' then
    update public.residents set room = p_value where id = p_id;
  elsif p_field = 'move_in_date' then
    update public.residents set move_in_date = p_value::date where id = p_id;
  elsif p_field = 'is_active' then
    update public.residents set is_active = coalesce(p_value::boolean, true) where id = p_id;
  else
    raise exception '変更できない項目です: %', p_field;
  end if;
end;
$$;

-- 関数を呼べるのは公開キー(anon)だけ。中で合言葉を確認する
revoke all on function public.check_passcode(text)                                 from public, anon, authenticated;
revoke all on function public.get_residents(text)                                  from public, anon, authenticated;
revoke all on function public.add_resident(text, text, text, text, date)           from public, anon, authenticated;
revoke all on function public.update_resident_field(text, uuid, text, text)        from public, anon, authenticated;
grant execute on function public.check_passcode(text)                              to anon;
grant execute on function public.get_residents(text)                               to anon;
grant execute on function public.add_resident(text, text, text, text, date)        to anon;
grant execute on function public.update_resident_field(text, uuid, text, text)     to anon;
