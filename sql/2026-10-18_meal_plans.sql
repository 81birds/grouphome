-- =====================================================
-- 食事の予定(食べる ○ / 食べない ×)
--   ・meal_plans … 1 行 =「どの利用者さんが・何日の・どの食事を・食べるか」
--       meal は breakfast(朝食)/ lunch(昼食)/ dinner(夕食)
--       昼食は土日だけ(平日は朝と夕)。set_meal_plan で止める
--       まだ選んでいない食事は行がない(未回答)
--   ・利用者さんの画面(family.html)で ○ / × を選び、食数管理(meals.html)で数える
--   ・ハウスは持たない。その日に入居している部屋(room_assignments)から決める
-- 方針は 2026-10-10_init.sql と同じ(テーブル直接アクセス不可・関数経由)
-- =====================================================

create table if not exists public.meal_plans (
  id           uuid primary key default gen_random_uuid(),
  resident_id  uuid not null references public.residents(id),
  meal_date    date not null,
  meal         text not null check (meal in ('breakfast', 'lunch', 'dinner')),
  will_eat     boolean not null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (resident_id, meal_date, meal)
);

create index if not exists meal_plans_date_idx on public.meal_plans (meal_date);

comment on table  public.meal_plans           is '食事の予定(食べる・食べない)';
comment on column public.meal_plans.meal      is 'breakfast / lunch / dinner';
comment on column public.meal_plans.will_eat  is 'true = 食べる(○)、false = 食べない(×)';

create or replace trigger meal_plans_set_updated_at
  before update on public.meal_plans
  for each row execute function public.set_updated_at();

alter table public.meal_plans enable row level security;
revoke all on public.meal_plans from anon, authenticated;

-- ----- 関数 -----
-- 期間の食事の予定。p_resident_id を渡せばその人だけ
create or replace function public.get_meal_plans(input_passcode text, p_from date, p_to date, p_resident_id uuid default null)
returns setof public.meal_plans
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_passcode(input_passcode);
  return query
    select * from public.meal_plans m
     where m.meal_date between p_from and p_to
       and (p_resident_id is null or m.resident_id = p_resident_id)
     order by m.meal_date, m.resident_id, m.meal;
end;
$$;

-- 食べる・食べないを決める(同じ日・同じ食事は書き換え)
create or replace function public.set_meal_plan(input_passcode text, p_resident_id uuid, p_date date, p_meal text, p_will_eat boolean)
returns public.meal_plans
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.meal_plans;
begin
  perform public.check_passcode(input_passcode);
  if p_resident_id is null or p_date is null or p_will_eat is null then
    raise exception '利用者さん・日にち・食べるかどうかを入れてください';
  end if;
  if p_meal not in ('breakfast', 'lunch', 'dinner') then
    raise exception '食事の種類が正しくありません';
  end if;
  if p_meal = 'lunch' and extract(isodow from p_date) <= 5 then
    raise exception '平日の昼食はありません';
  end if;
  if not exists (select 1 from public.residents r where r.id = p_resident_id) then
    raise exception 'この利用者さんが見つかりません';
  end if;

  insert into public.meal_plans (resident_id, meal_date, meal, will_eat)
  values (p_resident_id, p_date, p_meal, p_will_eat)
  on conflict (resident_id, meal_date, meal) do update set will_eat = excluded.will_eat
  returning * into v_row;
  return v_row;
end;
$$;

-- ----- 権限(呼べるのは公開キーだけ。中で合言葉を確認する) -----
revoke all on function public.get_meal_plans(text, date, date, uuid)          from public, anon, authenticated;
revoke all on function public.set_meal_plan(text, uuid, date, text, boolean)  from public, anon, authenticated;
grant execute on function public.get_meal_plans(text, date, date, uuid)       to anon;
grant execute on function public.set_meal_plan(text, uuid, date, text, boolean) to anon;
