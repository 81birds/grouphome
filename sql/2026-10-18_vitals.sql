-- =====================================================
-- バイタル(利用者さんが自分で入れる体調の記録)
--   ・vitals … 1 行 =「どの利用者さんが・何日の何時に・はかった値」
--       体温・血圧(上 / 下)・脈拍は、はかったものだけ入れる(空でもよい。ただし何か 1 つは要る)
--       bath_prev_day … 前日に お風呂(bath)/ シャワー(shower)。空 = 答えていない
--       entered_by … resident(利用者さんの画面)/ staff
--   ・ハウスは持たない。その日に入居している部屋から決める(meal_plans と同じ)
--   ・記録は消さない。間違いは void_vital で取り消す(voided_at)
--   ・利用者さんの画面(family.html)で入れ、バイタル(vitals.html)で見る
-- 方針は 2026-10-10_init.sql と同じ(テーブル直接アクセス不可・関数経由・論理削除)
-- =====================================================

create table if not exists public.vitals (
  id             uuid primary key default gen_random_uuid(),
  resident_id    uuid not null references public.residents(id),
  measured_date  date not null,
  measured_time  time not null,
  temperature    numeric(3,1) check (temperature between 34.0 and 42.0),
  bp_high        integer check (bp_high between 50 and 260),
  bp_low         integer check (bp_low between 30 and 160),
  pulse          integer check (pulse between 30 and 200),
  bath_prev_day  text check (bath_prev_day in ('bath', 'shower')),
  entered_by     text not null default 'resident' check (entered_by in ('resident', 'staff')),
  voided_at      timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create index if not exists vitals_date_idx on public.vitals (measured_date) where voided_at is null;
create index if not exists vitals_resident_idx on public.vitals (resident_id, measured_date) where voided_at is null;

comment on table  public.vitals               is 'バイタル(体温・血圧・脈拍・前日の入浴)';
comment on column public.vitals.temperature   is '体温(℃)';
comment on column public.vitals.bp_high       is '血圧の上(mmHg)';
comment on column public.vitals.bp_low        is '血圧の下(mmHg)';
comment on column public.vitals.pulse         is '脈拍(回/分)';
comment on column public.vitals.bath_prev_day is '前日の入浴: bath = お風呂 / shower = シャワー / 空 = 答えていない';
comment on column public.vitals.entered_by    is 'resident = 利用者さんが入れた / staff = スタッフが入れた';
comment on column public.vitals.voided_at     is '取り消した日時(入力の間違いなど)';

create or replace trigger vitals_set_updated_at
  before update on public.vitals
  for each row execute function public.set_updated_at();

alter table public.vitals enable row level security;
revoke all on public.vitals from anon, authenticated;

-- ----- 関数 -----
-- 期間のバイタル(取り消したものは出さない)。p_resident_id を渡せばその人だけ
create or replace function public.get_vitals(input_passcode text, p_from date, p_to date, p_resident_id uuid default null)
returns setof public.vitals
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_passcode(input_passcode);
  return query
    select * from public.vitals v
     where v.measured_date between p_from and p_to
       and v.voided_at is null
       and (p_resident_id is null or v.resident_id = p_resident_id)
     order by v.measured_date, v.measured_time, v.created_at;
end;
$$;

-- バイタルを入れる
create or replace function public.add_vital(
  input_passcode text,
  p_resident_id uuid,
  p_date date,
  p_time time,
  p_temperature numeric,
  p_bp_high integer,
  p_bp_low integer,
  p_pulse integer,
  p_bath text,
  p_by text default 'resident'
)
returns public.vitals
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.vitals;
begin
  perform public.check_passcode(input_passcode);
  if p_resident_id is null or p_date is null or p_time is null then
    raise exception '利用者さん・日にち・はかった時間を入れてください';
  end if;
  if p_temperature is null and p_bp_high is null and p_bp_low is null and p_pulse is null and p_bath is null then
    raise exception 'はかった値を 1 つ以上入れてください';
  end if;
  if (p_bp_high is null) <> (p_bp_low is null) then
    raise exception '血圧は上と下の両方を入れてください';
  end if;
  if p_temperature is not null and (p_temperature < 34 or p_temperature > 42) then
    raise exception '体温は 34.0〜42.0 で入れてください';
  end if;
  if p_bp_high is not null and (p_bp_high < 50 or p_bp_high > 260 or p_bp_low < 30 or p_bp_low > 160 or p_bp_low >= p_bp_high) then
    raise exception '血圧の値を確かめてください(上 50〜260・下 30〜160、上のほうが大きい)';
  end if;
  if p_pulse is not null and (p_pulse < 30 or p_pulse > 200) then
    raise exception '脈拍は 30〜200 で入れてください';
  end if;
  if p_bath is not null and p_bath not in ('bath', 'shower') then
    raise exception '入浴の選び方が正しくありません';
  end if;
  if coalesce(p_by, '') not in ('resident', 'staff') then
    raise exception '誰が入れたかが正しくありません';
  end if;
  if not exists (select 1 from public.residents r where r.id = p_resident_id) then
    raise exception 'この利用者さんが見つかりません';
  end if;

  insert into public.vitals (resident_id, measured_date, measured_time, temperature, bp_high, bp_low, pulse, bath_prev_day, entered_by)
  values (p_resident_id, p_date, p_time, p_temperature, p_bp_high, p_bp_low, p_pulse, p_bath, p_by)
  returning * into v_row;
  return v_row;
end;
$$;

-- 入力の間違いを取り消す(記録は残し、voided_at を入れる)
create or replace function public.void_vital(input_passcode text, p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_passcode(input_passcode);
  update public.vitals set voided_at = now() where id = p_id and voided_at is null;
end;
$$;

-- ----- 権限(呼べるのは公開キーだけ。中で合言葉を確認する) -----
revoke all on function public.get_vitals(text, date, date, uuid)                                            from public, anon, authenticated;
revoke all on function public.add_vital(text, uuid, date, time, numeric, integer, integer, integer, text, text) from public, anon, authenticated;
revoke all on function public.void_vital(text, uuid)                                                         from public, anon, authenticated;
grant execute on function public.get_vitals(text, date, date, uuid)                                          to anon;
grant execute on function public.add_vital(text, uuid, date, time, numeric, integer, integer, integer, text, text) to anon;
grant execute on function public.void_vital(text, uuid)                                                       to anon;
