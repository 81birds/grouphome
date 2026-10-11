-- =====================================================
-- 部屋と入居
--   ・rooms             … 施設の部屋(101 号室など)
--   ・room_assignments  … 入居 1 件 =「どの利用者が・どの部屋に・いつから・いつまで」
--       期間は [move_in_date, move_out_date)。move_out_date が空なら今も入居中
--       退居日にはその部屋は空いている(同じ日に次の人が入居できる)
--       1 つの部屋に同じ期間 2 人は入れない。同じ利用者が同じ期間に 2 部屋にも入れない
--       今の部屋から別の部屋に入居させると、前の部屋はその日で退居扱いにする(部屋の移動)
--   ・residents.room / move_in_date は使わなくなる(入居の記録に移った)
-- 方針は 2026-10-10_init.sql と同じ(テーブル直接アクセス不可・関数経由・論理削除)
-- =====================================================

comment on column public.residents.room         is '使わない(2026-10-11 から room_assignments に移った)';
comment on column public.residents.move_in_date is '使わない(2026-10-11 から room_assignments に移った)';

-- ----- 部屋 -----
create table if not exists public.rooms (
  id          uuid primary key default gen_random_uuid(),
  house_id    uuid not null references public.houses(id),
  name        text not null check (length(trim(name)) > 0),
  sort_order  integer not null default 0,
  note        text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists rooms_house_idx on public.rooms (house_id);

comment on table  public.rooms           is '部屋';
comment on column public.rooms.name      is '部屋名(101 など)';
comment on column public.rooms.is_active is '使っている部屋なら true';

create or replace trigger rooms_set_updated_at
  before update on public.rooms
  for each row execute function public.set_updated_at();

alter table public.rooms enable row level security;
revoke all on public.rooms from anon, authenticated;

-- ----- 入居 -----
create table if not exists public.room_assignments (
  id             uuid primary key default gen_random_uuid(),
  resident_id    uuid not null references public.residents(id),
  room_id        uuid not null references public.rooms(id),
  move_in_date   date not null,
  move_out_date  date check (move_out_date is null or move_out_date > move_in_date),
  note           text,
  voided_at      timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create index if not exists room_assignments_resident_idx on public.room_assignments (resident_id) where voided_at is null;
create index if not exists room_assignments_room_idx     on public.room_assignments (room_id)     where voided_at is null;

comment on table  public.room_assignments               is '入居(利用者と部屋のつながり。履歴も残す)';
comment on column public.room_assignments.move_in_date  is '入居日';
comment on column public.room_assignments.move_out_date is '退居日(空なら入居中)。この日から部屋は空く';
comment on column public.room_assignments.voided_at     is '取り消した日時(登録の間違いなど)';

create or replace trigger room_assignments_set_updated_at
  before update on public.room_assignments
  for each row execute function public.set_updated_at();

alter table public.room_assignments enable row level security;
revoke all on public.room_assignments from anon, authenticated;

-- ----- 部屋の関数 -----
create or replace function public.get_rooms(input_passcode text)
returns setof public.rooms
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_passcode(input_passcode);
  return query
    select * from public.rooms r
     order by r.house_id, r.is_active desc, r.sort_order, r.name;
end;
$$;

create or replace function public.add_room(input_passcode text, p_house_id uuid, p_name text)
returns public.rooms
language plpgsql
security definer
set search_path = ''
as $$
declare
  row public.rooms;
begin
  perform public.check_passcode(input_passcode);
  if exists (select 1 from public.rooms r where r.house_id = p_house_id and r.name = trim(p_name) and r.is_active) then
    raise exception '%号室はすでにあります', trim(p_name);
  end if;
  insert into public.rooms (house_id, name, sort_order)
  values (p_house_id, trim(p_name),
          coalesce((select max(sort_order) from public.rooms r where r.house_id = p_house_id), 0) + 10)
  returning * into row;
  return row;
end;
$$;

create or replace function public.update_room_field(input_passcode text, p_id uuid, p_field text, p_value text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_passcode(input_passcode);
  p_value := nullif(trim(p_value), '');

  if p_field = 'name' then
    if p_value is null then raise exception '部屋名は空にできません'; end if;
    update public.rooms set name = p_value where id = p_id;
  elsif p_field = 'note' then
    update public.rooms set note = p_value where id = p_id;
  elsif p_field = 'sort_order' then
    update public.rooms set sort_order = coalesce(p_value::integer, 0) where id = p_id;
  elsif p_field = 'is_active' then
    if coalesce(p_value::boolean, true) = false and exists (
      select 1 from public.room_assignments a
       where a.room_id = p_id and a.voided_at is null
         and (a.move_out_date is null or a.move_out_date > current_date)
    ) then
      raise exception '入居している人がいる部屋は、使わない設定にできません';
    end if;
    update public.rooms set is_active = coalesce(p_value::boolean, true) where id = p_id;
  else
    raise exception '変更できない項目です: %', p_field;
  end if;
end;
$$;

-- ----- 入居の関数 -----
create or replace function public.get_room_assignments(input_passcode text)
returns setof public.room_assignments
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_passcode(input_passcode);
  return query
    select * from public.room_assignments a
     where a.voided_at is null
     order by a.move_in_date desc, a.created_at desc;
end;
$$;

-- 入居させる。今ほかの部屋に入居中なら、その部屋は入居日で退居扱いにする(部屋の移動)
create or replace function public.assign_room(
  input_passcode text,
  p_resident_id uuid,
  p_room_id uuid,
  p_move_in_date date,
  p_note text default null
)
returns public.room_assignments
language plpgsql
security definer
set search_path = ''
as $$
declare
  row public.room_assignments;
  clash record;
  mine record;
begin
  perform public.check_passcode(input_passcode);
  if p_resident_id is null or p_room_id is null or p_move_in_date is null then
    raise exception '利用者・部屋・入居日を入れてください';
  end if;
  if not exists (select 1 from public.rooms r where r.id = p_room_id and r.is_active) then
    raise exception 'この部屋は使えません';
  end if;

  -- この部屋に、入居日以降ほかの人がいないか
  select a.move_in_date, a.move_out_date, p.name as resident_name
    into clash
    from public.room_assignments a
    join public.residents p on p.id = a.resident_id
   where a.room_id = p_room_id
     and a.voided_at is null
     and a.resident_id <> p_resident_id
     and daterange(a.move_in_date, a.move_out_date, '[)') && daterange(p_move_in_date, null, '[)')
   order by a.move_in_date
   limit 1;
  if found then
    raise exception 'この部屋には %さんが入居しています(% から)', clash.resident_name, to_char(clash.move_in_date, 'YYYY/MM/DD');
  end if;

  -- この利用者の、入居日以降にかかる入居
  for mine in
    select a.* from public.room_assignments a
     where a.resident_id = p_resident_id
       and a.voided_at is null
       and daterange(a.move_in_date, a.move_out_date, '[)') && daterange(p_move_in_date, null, '[)')
  loop
    if mine.room_id = p_room_id and mine.move_out_date is null then
      raise exception 'すでにこの部屋に入居しています';
    elsif mine.move_out_date is null and mine.move_in_date < p_move_in_date then
      update public.room_assignments set move_out_date = p_move_in_date where id = mine.id;
    else
      raise exception '% から別の部屋に入居している記録があります。先にそちらを直してください', to_char(mine.move_in_date, 'YYYY/MM/DD');
    end if;
  end loop;

  insert into public.room_assignments (resident_id, room_id, move_in_date, note)
  values (p_resident_id, p_room_id, p_move_in_date, nullif(trim(p_note), ''))
  returning * into row;
  return row;
end;
$$;

-- 退居させる(退居日を入れる)
create or replace function public.end_room_assignment(input_passcode text, p_id uuid, p_move_out_date date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  a public.room_assignments;
begin
  perform public.check_passcode(input_passcode);
  select * into a from public.room_assignments where id = p_id and voided_at is null;
  if not found then raise exception 'この入居の記録が見つかりません'; end if;
  if p_move_out_date is null or p_move_out_date <= a.move_in_date then
    raise exception '退居日は入居日(%)より後の日にしてください', to_char(a.move_in_date, 'YYYY/MM/DD');
  end if;
  if exists (
    select 1 from public.room_assignments b
     where b.resident_id = a.resident_id and b.voided_at is null and b.id <> a.id
       and b.move_in_date >= a.move_in_date and b.move_in_date < p_move_out_date
  ) then
    raise exception '退居日までの間に、別の部屋への入居の記録があります';
  end if;
  update public.room_assignments set move_out_date = p_move_out_date where id = p_id;
end;
$$;

-- 登録の間違いを取り消す(記録は残し、voided_at を入れる)
create or replace function public.void_room_assignment(input_passcode text, p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_passcode(input_passcode);
  update public.room_assignments set voided_at = now() where id = p_id and voided_at is null;
end;
$$;

-- ----- 権限(呼べるのは公開キーだけ。中で合言葉を確認する) -----
revoke all on function public.get_rooms(text)                                       from public, anon, authenticated;
revoke all on function public.add_room(text, uuid, text)                            from public, anon, authenticated;
revoke all on function public.update_room_field(text, uuid, text, text)             from public, anon, authenticated;
revoke all on function public.get_room_assignments(text)                            from public, anon, authenticated;
revoke all on function public.assign_room(text, uuid, uuid, date, text)             from public, anon, authenticated;
revoke all on function public.end_room_assignment(text, uuid, date)                 from public, anon, authenticated;
revoke all on function public.void_room_assignment(text, uuid)                      from public, anon, authenticated;
grant execute on function public.get_rooms(text)                                    to anon;
grant execute on function public.add_room(text, uuid, text)                         to anon;
grant execute on function public.update_room_field(text, uuid, text, text)          to anon;
grant execute on function public.get_room_assignments(text)                         to anon;
grant execute on function public.assign_room(text, uuid, uuid, date, text)          to anon;
grant execute on function public.end_room_assignment(text, uuid, date)              to anon;
grant execute on function public.void_room_assignment(text, uuid)                   to anon;
