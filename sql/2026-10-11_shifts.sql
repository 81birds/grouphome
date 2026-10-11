-- =====================================================
-- 勤務表
--   ・houses.short_name … 勤務表のマスに出す施設の略称
--   ・shift_types       … 勤務区分(夜勤など)。時間の初期値を持つ
--   ・shifts            … 勤務 1 件 =「いつ・誰が・どの施設に・何時から何時まで」
--       work_date は勤務が始まる日。end_time <= start_time なら翌日に終わる(夜勤 22:00〜翌10:00)
--       同じスタッフで時間が重なる勤務は保存できない
-- 方針は 2026-10-10_init.sql と同じ(テーブル直接アクセス不可・関数経由・論理削除)
-- =====================================================

-- ----- 施設の略称 -----
alter table public.houses add column if not exists short_name text;
comment on column public.houses.short_name is '略称(勤務表のマスに出す。例: みどり)';

drop function if exists public.add_house(text, text, text, text, integer);
create or replace function public.add_house(
  input_passcode text,
  p_name text,
  p_short_name text default null,
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
  insert into public.houses (name, short_name, address, phone, capacity)
  values (trim(p_name), nullif(trim(p_short_name), ''), nullif(trim(p_address), ''),
          nullif(trim(p_phone), ''), p_capacity)
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
  elsif p_field = 'short_name' then
    update public.houses set short_name = p_value where id = p_id;
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

-- ----- 勤務区分 -----
create table if not exists public.shift_types (
  id           uuid primary key default gen_random_uuid(),
  name         text not null check (length(trim(name)) > 0),
  short_label  text,
  start_time   time not null,
  end_time     time not null check (end_time <> start_time),
  sort_order   integer not null default 0,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

comment on table  public.shift_types             is '勤務区分';
comment on column public.shift_types.name        is '区分名(夜勤・日勤など)';
comment on column public.shift_types.short_label is '勤務表に出す 1〜2 文字(夜・日など)';
comment on column public.shift_types.start_time  is '開始時刻の初期値';
comment on column public.shift_types.end_time    is '終了時刻の初期値(開始より前なら翌日)';

drop trigger if exists shift_types_set_updated_at on public.shift_types;
create trigger shift_types_set_updated_at
  before update on public.shift_types
  for each row execute function public.set_updated_at();

alter table public.shift_types enable row level security;
revoke all on public.shift_types from anon, authenticated;

-- 最初の区分: 夜勤 22:00〜翌10:00
insert into public.shift_types (name, short_label, start_time, end_time, sort_order)
select '夜勤', '夜', '22:00', '10:00', 90
where not exists (select 1 from public.shift_types where name = '夜勤');

-- ----- 勤務 -----
create table if not exists public.shifts (
  id             uuid primary key default gen_random_uuid(),
  work_date      date not null,
  staff_id       uuid not null references public.staff(id),
  house_id       uuid not null references public.houses(id),
  shift_type_id  uuid references public.shift_types(id),
  start_time     time not null,
  end_time       time not null check (end_time <> start_time),
  note           text,
  voided_at      timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create index if not exists shifts_work_date_idx on public.shifts (work_date) where voided_at is null;
create index if not exists shifts_staff_idx     on public.shifts (staff_id, work_date) where voided_at is null;
create index if not exists shifts_house_idx     on public.shifts (house_id, work_date) where voided_at is null;

comment on table  public.shifts           is '勤務(シフト)';
comment on column public.shifts.work_date is '勤務が始まる日';
comment on column public.shifts.end_time  is '終了時刻。開始時刻より前なら翌日に終わる';
comment on column public.shifts.voided_at is '削除した日時(論理削除)';

drop trigger if exists shifts_set_updated_at on public.shifts;
create trigger shifts_set_updated_at
  before update on public.shifts
  for each row execute function public.set_updated_at();

alter table public.shifts enable row level security;
revoke all on public.shifts from anon, authenticated;

-- 勤務の時間帯(日付またぎを含む)。重なりの判定に使う
create or replace function public.shift_range(p_date date, p_start time, p_end time)
returns tsrange
language sql
immutable
set search_path = ''
as $$
  select tsrange(
    p_date + p_start,
    p_date + p_end + case when p_end <= p_start then interval '1 day' else interval '0' end,
    '[)'
  );
$$;
revoke all on function public.shift_range(date, time, time) from public, anon, authenticated;

-- ----- 勤務区分の関数 -----
create or replace function public.get_shift_types(input_passcode text)
returns setof public.shift_types
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_passcode(input_passcode);
  return query
    select * from public.shift_types t
     order by t.is_active desc, t.start_time, t.name;
end;
$$;

create or replace function public.add_shift_type(
  input_passcode text,
  p_name text,
  p_short_label text,
  p_start_time time,
  p_end_time time
)
returns public.shift_types
language plpgsql
security definer
set search_path = ''
as $$
declare
  row public.shift_types;
begin
  perform public.check_passcode(input_passcode);
  insert into public.shift_types (name, short_label, start_time, end_time, sort_order)
  values (trim(p_name), nullif(trim(p_short_label), ''), p_start_time, p_end_time,
          coalesce((select max(sort_order) from public.shift_types), 0) + 10)
  returning * into row;
  return row;
end;
$$;

create or replace function public.update_shift_type_field(
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
    if p_value is null then raise exception '区分名は空にできません'; end if;
    update public.shift_types set name = p_value where id = p_id;
  elsif p_field = 'short_label' then
    update public.shift_types set short_label = p_value where id = p_id;
  elsif p_field = 'start_time' then
    if p_value is null then raise exception '開始時刻は空にできません'; end if;
    update public.shift_types set start_time = p_value::time where id = p_id;
  elsif p_field = 'end_time' then
    if p_value is null then raise exception '終了時刻は空にできません'; end if;
    update public.shift_types set end_time = p_value::time where id = p_id;
  elsif p_field = 'is_active' then
    update public.shift_types set is_active = coalesce(p_value::boolean, true) where id = p_id;
  else
    raise exception '変更できない項目です: %', p_field;
  end if;
end;
$$;

-- ----- 勤務の関数 -----
-- 期間内に始まる勤務と、前日に始まって期間内にかかる勤務(夜勤)を返す
create or replace function public.get_shifts(input_passcode text, p_from date, p_to date)
returns setof public.shifts
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_passcode(input_passcode);
  return query
    select * from public.shifts s
     where s.voided_at is null
       and s.work_date between p_from - 1 and p_to
     order by s.work_date, s.start_time;
end;
$$;

-- 追加(p_id が null)または変更。同じスタッフの勤務と時間が重なると保存しない
create or replace function public.save_shift(
  input_passcode text,
  p_id uuid,
  p_work_date date,
  p_staff_id uuid,
  p_house_id uuid,
  p_shift_type_id uuid,
  p_start_time time,
  p_end_time time,
  p_note text default null
)
returns public.shifts
language plpgsql
security definer
set search_path = ''
as $$
declare
  row public.shifts;
  clash record;
begin
  perform public.check_passcode(input_passcode);

  if p_work_date is null or p_staff_id is null or p_house_id is null
     or p_start_time is null or p_end_time is null then
    raise exception '日付・スタッフ・施設・時間を入れてください';
  end if;
  if p_start_time = p_end_time then
    raise exception '開始と終了が同じ時刻です';
  end if;

  select s.work_date, s.start_time, s.end_time, h.name as house_name
    into clash
    from public.shifts s
    join public.houses h on h.id = s.house_id
   where s.staff_id = p_staff_id
     and s.voided_at is null
     and s.id is distinct from p_id
     and s.work_date between p_work_date - 1 and p_work_date + 1
     and public.shift_range(s.work_date, s.start_time, s.end_time)
         && public.shift_range(p_work_date, p_start_time, p_end_time)
   limit 1;

  if found then
    raise exception '時間が重なる勤務があります(% % %〜%)',
      to_char(clash.work_date, 'MM/DD'), clash.house_name,
      to_char(clash.start_time, 'HH24:MI'), to_char(clash.end_time, 'HH24:MI');
  end if;

  if p_id is null then
    insert into public.shifts (work_date, staff_id, house_id, shift_type_id, start_time, end_time, note)
    values (p_work_date, p_staff_id, p_house_id, p_shift_type_id, p_start_time, p_end_time, nullif(trim(p_note), ''))
    returning * into row;
  else
    update public.shifts
       set work_date = p_work_date, staff_id = p_staff_id, house_id = p_house_id,
           shift_type_id = p_shift_type_id, start_time = p_start_time, end_time = p_end_time,
           note = nullif(trim(p_note), '')
     where id = p_id and voided_at is null
    returning * into row;
    if not found then raise exception 'この勤務は見つかりませんでした'; end if;
  end if;
  return row;
end;
$$;

create or replace function public.void_shift(input_passcode text, p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_passcode(input_passcode);
  update public.shifts set voided_at = now() where id = p_id and voided_at is null;
end;
$$;

-- ----- 権限(呼べるのは公開キーだけ。中で合言葉を確認する) -----
revoke all on function public.add_house(text, text, text, text, text, integer)                       from public, anon, authenticated;
revoke all on function public.update_house_field(text, uuid, text, text)                             from public, anon, authenticated;
revoke all on function public.get_shift_types(text)                                                  from public, anon, authenticated;
revoke all on function public.add_shift_type(text, text, text, time, time)                           from public, anon, authenticated;
revoke all on function public.update_shift_type_field(text, uuid, text, text)                        from public, anon, authenticated;
revoke all on function public.get_shifts(text, date, date)                                           from public, anon, authenticated;
revoke all on function public.save_shift(text, uuid, date, uuid, uuid, uuid, time, time, text)       from public, anon, authenticated;
revoke all on function public.void_shift(text, uuid)                                                 from public, anon, authenticated;
grant execute on function public.add_house(text, text, text, text, text, integer)                    to anon;
grant execute on function public.update_house_field(text, uuid, text, text)                          to anon;
grant execute on function public.get_shift_types(text)                                               to anon;
grant execute on function public.add_shift_type(text, text, text, time, time)                        to anon;
grant execute on function public.update_shift_type_field(text, uuid, text, text)                     to anon;
grant execute on function public.get_shifts(text, date, date)                                        to anon;
grant execute on function public.save_shift(text, uuid, date, uuid, uuid, uuid, time, time, text)    to anon;
grant execute on function public.void_shift(text, uuid)                                              to anon;
