-- =====================================================
-- 食事の予定: 利用者さんが選んだか、スタッフが変えたかを残す
--   ・meal_plans.set_by … 'resident'(利用者さんの画面)/ 'staff'(食数管理の画面)
--       いまある行は利用者さんが選んだものなので 'resident'
--   ・set_meal_plan に p_by を足す(なければ 'resident')。
--       前の関数(引数 5 つ)は名前を変えて使わないようにする
-- =====================================================

alter table public.meal_plans
  add column if not exists set_by text not null default 'resident'
  check (set_by in ('resident', 'staff'));

comment on column public.meal_plans.set_by is 'resident = 利用者さんが選んだ / staff = スタッフが変えた';

-- 前の関数は使わない(引数を変えるため)
alter function public.set_meal_plan(text, uuid, date, text, boolean) rename to set_meal_plan_unused_20261018;
revoke all on function public.set_meal_plan_unused_20261018(text, uuid, date, text, boolean) from public, anon, authenticated;

create or replace function public.set_meal_plan(
  input_passcode text,
  p_resident_id uuid,
  p_date date,
  p_meal text,
  p_will_eat boolean,
  p_by text default 'resident'
)
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
  if coalesce(p_by, '') not in ('resident', 'staff') then
    raise exception '誰が選んだかが正しくありません';
  end if;
  if p_meal = 'lunch' and extract(isodow from p_date) <= 5 then
    raise exception '平日の昼食はありません';
  end if;
  if not exists (select 1 from public.residents r where r.id = p_resident_id) then
    raise exception 'この利用者さんが見つかりません';
  end if;

  insert into public.meal_plans (resident_id, meal_date, meal, will_eat, set_by)
  values (p_resident_id, p_date, p_meal, p_will_eat, p_by)
  on conflict (resident_id, meal_date, meal) do update set will_eat = excluded.will_eat, set_by = excluded.set_by
  returning * into v_row;
  return v_row;
end;
$$;

revoke all on function public.set_meal_plan(text, uuid, date, text, boolean, text) from public, anon, authenticated;
grant execute on function public.set_meal_plan(text, uuid, date, text, boolean, text) to anon;
