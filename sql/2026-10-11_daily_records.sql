-- =====================================================
-- 日々の記録
--   ・daily_records … 記録 1 件 =「どの利用者に・どの施設で・何日の何時に・何をしたか」
--       kind は画面のチップの名前(朝食・昼食・夕食・外出・出勤・通所・お薬おわたし・お薬空包確認)
--       チップの種類は records.html の KINDS で増やせる(DB の変更はいらない)
--       house_id は記録したときの施設(あとで部屋を移っても、記録の場所は変わらない)
--   ・記録は消さない。間違いは void_daily_record で取り消す(voided_at)
-- 方針は 2026-10-10_init.sql と同じ(テーブル直接アクセス不可・関数経由・論理削除)
-- =====================================================

create table if not exists public.daily_records (
  id           uuid primary key default gen_random_uuid(),
  resident_id  uuid not null references public.residents(id),
  house_id     uuid not null references public.houses(id),
  record_date  date not null,
  record_time  time not null,
  kind         text not null check (length(trim(kind)) > 0),
  note         text,
  voided_at    timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists daily_records_house_date_idx
  on public.daily_records (house_id, record_date) where voided_at is null;
create index if not exists daily_records_resident_date_idx
  on public.daily_records (resident_id, record_date) where voided_at is null;

comment on table  public.daily_records             is '日々の記録(食事・外出・服薬など)';
comment on column public.daily_records.house_id    is '記録したときの施設';
comment on column public.daily_records.record_date is '記録の日';
comment on column public.daily_records.record_time is '記録の時刻';
comment on column public.daily_records.kind        is '内容(朝食・外出・お薬おわたし など)';
comment on column public.daily_records.note        is 'ひとことメモ(今は画面で使っていない)';
comment on column public.daily_records.voided_at   is '取り消した日時(入力の間違いなど)';

create or replace trigger daily_records_set_updated_at
  before update on public.daily_records
  for each row execute function public.set_updated_at();

alter table public.daily_records enable row level security;
revoke all on public.daily_records from anon, authenticated;

-- ----- 関数 -----
-- ある施設・ある日の記録(取り消したものは出さない)
create or replace function public.get_daily_records(input_passcode text, p_house_id uuid, p_date date)
returns setof public.daily_records
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_passcode(input_passcode);
  return query
    select * from public.daily_records d
     where d.house_id = p_house_id
       and d.record_date = p_date
       and d.voided_at is null
     order by d.record_time, d.created_at;
end;
$$;

-- 記録する。チップを複数選んだときは、内容ごとに 1 行ずつ作る
create or replace function public.add_daily_records(
  input_passcode text,
  p_resident_id uuid,
  p_house_id uuid,
  p_date date,
  p_time time,
  p_kinds text[],
  p_note text default null
)
returns setof public.daily_records
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_passcode(input_passcode);
  if p_resident_id is null or p_house_id is null or p_date is null or p_time is null then
    raise exception '利用者・施設・日にち・時刻を入れてください';
  end if;
  if p_kinds is null or coalesce(array_length(p_kinds, 1), 0) = 0 then
    raise exception '記録する内容を選んでください';
  end if;
  if not exists (select 1 from public.residents r where r.id = p_resident_id) then
    raise exception 'この利用者が見つかりません';
  end if;
  if not exists (select 1 from public.houses h where h.id = p_house_id) then
    raise exception 'この施設が見つかりません';
  end if;

  return query
    insert into public.daily_records (resident_id, house_id, record_date, record_time, kind, note)
    select p_resident_id, p_house_id, p_date, p_time, trim(k), nullif(trim(p_note), '')
      from unnest(p_kinds) as k
     where length(trim(k)) > 0
    returning *;
end;
$$;

-- 入力の間違いを取り消す(記録は残し、voided_at を入れる)
create or replace function public.void_daily_record(input_passcode text, p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_passcode(input_passcode);
  update public.daily_records set voided_at = now() where id = p_id and voided_at is null;
end;
$$;

-- ----- 権限(呼べるのは公開キーだけ。中で合言葉を確認する) -----
revoke all on function public.get_daily_records(text, uuid, date)                              from public, anon, authenticated;
revoke all on function public.add_daily_records(text, uuid, uuid, date, time, text[], text)    from public, anon, authenticated;
revoke all on function public.void_daily_record(text, uuid)                                    from public, anon, authenticated;
grant execute on function public.get_daily_records(text, uuid, date)                           to anon;
grant execute on function public.add_daily_records(text, uuid, uuid, date, time, text[], text) to anon;
grant execute on function public.void_daily_record(text, uuid)                                 to anon;
