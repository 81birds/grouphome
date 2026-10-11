-- =====================================================
-- 施設とスタッフ
--   ・houses … グループホームの施設(住居)
--   ・staff  … スタッフ。所属施設を 1 つ持てる(未定でも可)
-- 方針は 2026-10-10_init.sql と同じ(テーブル直接アクセス不可・関数経由・論理削除)
-- =====================================================

-- ----- 施設 -----
create table if not exists public.houses (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (length(trim(name)) > 0),
  address     text,
  phone       text,
  capacity    integer check (capacity is null or capacity >= 0),
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table  public.houses           is '施設';
comment on column public.houses.name      is '施設名';
comment on column public.houses.address   is '住所';
comment on column public.houses.phone     is '電話番号';
comment on column public.houses.capacity  is '定員';
comment on column public.houses.is_active is '運営中なら true';

drop trigger if exists houses_set_updated_at on public.houses;
create trigger houses_set_updated_at
  before update on public.houses
  for each row execute function public.set_updated_at();

alter table public.houses enable row level security;
revoke all on public.houses from anon, authenticated;

-- ----- スタッフ -----
create table if not exists public.staff (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (length(trim(name)) > 0),
  kana        text,
  house_id    uuid references public.houses(id),
  job_title   text,
  phone       text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists staff_house_id_idx on public.staff (house_id);

comment on table  public.staff           is 'スタッフ';
comment on column public.staff.name      is '氏名';
comment on column public.staff.kana      is 'ふりがな';
comment on column public.staff.house_id  is '所属施設';
comment on column public.staff.job_title is '職種(世話人・生活支援員など)';
comment on column public.staff.phone     is '電話番号';
comment on column public.staff.is_active is '在籍中なら true、退職したら false';

drop trigger if exists staff_set_updated_at on public.staff;
create trigger staff_set_updated_at
  before update on public.staff
  for each row execute function public.set_updated_at();

alter table public.staff enable row level security;
revoke all on public.staff from anon, authenticated;

-- ----- 施設の関数 -----
create or replace function public.get_houses(input_passcode text)
returns setof public.houses
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_passcode(input_passcode);
  return query
    select * from public.houses h
     order by h.is_active desc, h.name, h.created_at;
end;
$$;

create or replace function public.add_house(
  input_passcode text,
  p_name text,
  p_address text default null,
  p_phone text default null,
  p_capacity integer default null
)
returns public.houses
language plpgsql
security definer
set search_path = ''
as $$
declare
  row public.houses;
begin
  perform public.check_passcode(input_passcode);
  insert into public.houses (name, address, phone, capacity)
  values (trim(p_name), nullif(trim(p_address), ''), nullif(trim(p_phone), ''), p_capacity)
  returning * into row;
  return row;
end;
$$;

create or replace function public.update_house_field(
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
    if p_value is null then raise exception '施設名は空にできません'; end if;
    update public.houses set name = p_value where id = p_id;
  elsif p_field = 'address' then
    update public.houses set address = p_value where id = p_id;
  elsif p_field = 'phone' then
    update public.houses set phone = p_value where id = p_id;
  elsif p_field = 'capacity' then
    update public.houses set capacity = p_value::integer where id = p_id;
  elsif p_field = 'is_active' then
    update public.houses set is_active = coalesce(p_value::boolean, true) where id = p_id;
  else
    raise exception '変更できない項目です: %', p_field;
  end if;
end;
$$;

-- ----- スタッフの関数 -----
create or replace function public.get_staff(input_passcode text)
returns setof public.staff
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_passcode(input_passcode);
  return query
    select * from public.staff s
     order by s.kana asc nulls last, s.name, s.created_at;
end;
$$;

create or replace function public.add_staff(
  input_passcode text,
  p_name text,
  p_kana text default null,
  p_house_id uuid default null,
  p_job_title text default null,
  p_phone text default null
)
returns public.staff
language plpgsql
security definer
set search_path = ''
as $$
declare
  row public.staff;
begin
  perform public.check_passcode(input_passcode);
  insert into public.staff (name, kana, house_id, job_title, phone)
  values (trim(p_name), nullif(trim(p_kana), ''), p_house_id,
          nullif(trim(p_job_title), ''), nullif(trim(p_phone), ''))
  returning * into row;
  return row;
end;
$$;

create or replace function public.update_staff_field(
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
    update public.staff set name = p_value where id = p_id;
  elsif p_field = 'kana' then
    update public.staff set kana = p_value where id = p_id;
  elsif p_field = 'house_id' then
    update public.staff set house_id = p_value::uuid where id = p_id;
  elsif p_field = 'job_title' then
    update public.staff set job_title = p_value where id = p_id;
  elsif p_field = 'phone' then
    update public.staff set phone = p_value where id = p_id;
  elsif p_field = 'is_active' then
    update public.staff set is_active = coalesce(p_value::boolean, true) where id = p_id;
  else
    raise exception '変更できない項目です: %', p_field;
  end if;
end;
$$;

-- ----- 権限(呼べるのは公開キーだけ。中で合言葉を確認する) -----
revoke all on function public.get_houses(text)                                       from public, anon, authenticated;
revoke all on function public.add_house(text, text, text, text, integer)             from public, anon, authenticated;
revoke all on function public.update_house_field(text, uuid, text, text)             from public, anon, authenticated;
revoke all on function public.get_staff(text)                                        from public, anon, authenticated;
revoke all on function public.add_staff(text, text, text, uuid, text, text)          from public, anon, authenticated;
revoke all on function public.update_staff_field(text, uuid, text, text)             from public, anon, authenticated;
grant execute on function public.get_houses(text)                                    to anon;
grant execute on function public.add_house(text, text, text, text, integer)          to anon;
grant execute on function public.update_house_field(text, uuid, text, text)          to anon;
grant execute on function public.get_staff(text)                                     to anon;
grant execute on function public.add_staff(text, text, text, uuid, text, text)       to anon;
grant execute on function public.update_staff_field(text, uuid, text, text)          to anon;
