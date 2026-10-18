-- =====================================================
-- 利用者さんの日課(基本のスケジュール)
--   ・resident_routines … 1 行 =「どの利用者さんが・何時に・何をするか(・何曜日に)」
--       content は自由に書く(通所・デイケア・通院 など)
--       weekdays は曜日の番号(0 = 日 … 6 = 土)の配列。空(または null)なら毎日
--   ・利用者さんDB のプロファイル(profile.html)で登録する
--   ・利用者さんの画面の「本日の予定」と、日々の記録の「きょうの日課」に出る
--   ・消さない。やめた日課は is_active = false
-- 方針は 2026-10-10_init.sql と同じ(テーブル直接アクセス不可・関数経由・論理削除)
-- =====================================================

create table if not exists public.resident_routines (
  id            uuid primary key default gen_random_uuid(),
  resident_id   uuid not null references public.residents(id),
  routine_time  time not null,
  content       text not null check (length(trim(content)) > 0),
  weekdays      smallint[] not null default '{}',
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists resident_routines_resident_idx on public.resident_routines (resident_id) where is_active;

comment on table  public.resident_routines          is '利用者さんの日課(基本のスケジュール)';
comment on column public.resident_routines.content  is '日課の内容(自由に書く)';
comment on column public.resident_routines.weekdays is '曜日(0 = 日 … 6 = 土)。空なら毎日';

create or replace trigger resident_routines_set_updated_at
  before update on public.resident_routines
  for each row execute function public.set_updated_at();

alter table public.resident_routines enable row level security;
revoke all on public.resident_routines from anon, authenticated;

-- ----- 関数 -----
-- 日課(やめたものは出さない)。p_resident_id を渡せばその人だけ
create or replace function public.get_routines(input_passcode text, p_resident_id uuid default null)
returns setof public.resident_routines
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_passcode(input_passcode);
  return query
    select * from public.resident_routines r
     where r.is_active
       and (p_resident_id is null or r.resident_id = p_resident_id)
     order by r.resident_id, r.routine_time, r.created_at;
end;
$$;

-- 日課を登録・変更する(p_id が null なら新しく作る)
create or replace function public.save_routine(
  input_passcode text,
  p_id uuid,
  p_resident_id uuid,
  p_time time,
  p_content text,
  p_weekdays smallint[]
)
returns public.resident_routines
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.resident_routines;
  v_days smallint[];
begin
  perform public.check_passcode(input_passcode);
  if p_resident_id is null or p_time is null or length(trim(coalesce(p_content, ''))) = 0 then
    raise exception '時間と内容を入れてください';
  end if;
  if exists (select 1 from unnest(coalesce(p_weekdays, '{}')) d where d < 0 or d > 6) then
    raise exception '曜日が正しくありません';
  end if;
  if not exists (select 1 from public.residents r where r.id = p_resident_id) then
    raise exception 'この利用者さんが見つかりません';
  end if;
  -- 曜日は重ねず、小さい順に
  select coalesce(array_agg(distinct d order by d), '{}') into v_days from unnest(coalesce(p_weekdays, '{}')) d;

  if p_id is null then
    insert into public.resident_routines (resident_id, routine_time, content, weekdays)
    values (p_resident_id, p_time, trim(p_content), v_days)
    returning * into v_row;
  else
    update public.resident_routines
       set routine_time = p_time, content = trim(p_content), weekdays = v_days
     where id = p_id and resident_id = p_resident_id and is_active
    returning * into v_row;
    if v_row.id is null then
      raise exception 'この日課が見つかりません';
    end if;
  end if;
  return v_row;
end;
$$;

-- 日課をやめる(消さずに is_active = false)
create or replace function public.end_routine(input_passcode text, p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_passcode(input_passcode);
  update public.resident_routines set is_active = false where id = p_id and is_active;
end;
$$;

-- ----- 権限(呼べるのは公開キーだけ。中で合言葉を確認する) -----
revoke all on function public.get_routines(text, uuid)                                from public, anon, authenticated;
revoke all on function public.save_routine(text, uuid, uuid, time, text, smallint[])  from public, anon, authenticated;
revoke all on function public.end_routine(text, uuid)                                 from public, anon, authenticated;
grant execute on function public.get_routines(text, uuid)                             to anon;
grant execute on function public.save_routine(text, uuid, uuid, time, text, smallint[]) to anon;
grant execute on function public.end_routine(text, uuid)                              to anon;
