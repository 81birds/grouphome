-- =====================================================
-- 服薬(朝・昼・夕・寝る前のお薬)と空包確認
--   ・resident_medications … 1 行 =「どの利用者さんが・いつ(朝・昼・夕・寝る前)・どのお薬(A〜D)を飲むか」
--       timing は morning / noon / evening / bedtime。1 人・1 つの時間で 1 行
--       medicines はお薬の種類(A・B・C・D)の配列。空ならその時間のお薬はない(行は消さない)
--   ・resident_med_settings … 1 行 = 1 人。empty_check = 空包確認をスタッフの日課に入れるか
--   ・服薬(medication.html)でスタッフが設定する
--   ・お薬は、日々の記録の「きょうの日課」と、利用者さんの画面の「本日の予定」に出る
--     空包確認は、日々の記録の「きょうの日課」だけに出る(スタッフの仕事)
-- 方針は 2026-10-10_init.sql と同じ(テーブル直接アクセス不可・関数経由・論理削除)
-- =====================================================

create table if not exists public.resident_medications (
  id            uuid primary key default gen_random_uuid(),
  resident_id   uuid not null references public.residents(id),
  timing        text not null check (timing in ('morning', 'noon', 'evening', 'bedtime')),
  medicines     text[] not null default '{}' check (medicines <@ array['A', 'B', 'C', 'D']),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (resident_id, timing)
);

comment on table  public.resident_medications           is '利用者さんのお薬(朝・昼・夕・寝る前)';
comment on column public.resident_medications.timing    is 'morning = 朝 / noon = 昼 / evening = 夕 / bedtime = 寝る前';
comment on column public.resident_medications.medicines is 'お薬の種類(A〜D)。空ならその時間のお薬はない';

create or replace trigger resident_medications_set_updated_at
  before update on public.resident_medications
  for each row execute function public.set_updated_at();

alter table public.resident_medications enable row level security;
revoke all on public.resident_medications from anon, authenticated;

create table if not exists public.resident_med_settings (
  resident_id   uuid primary key references public.residents(id),
  empty_check   boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table  public.resident_med_settings             is '利用者さんごとの服薬の設定(スタッフが決める)';
comment on column public.resident_med_settings.empty_check is '空包確認をスタッフの日課に入れるか';

create or replace trigger resident_med_settings_set_updated_at
  before update on public.resident_med_settings
  for each row execute function public.set_updated_at();

alter table public.resident_med_settings enable row level security;
revoke all on public.resident_med_settings from anon, authenticated;

-- ----- 関数 -----
-- お薬。p_resident_id を渡せばその人だけ
create or replace function public.get_medications(input_passcode text, p_resident_id uuid default null)
returns setof public.resident_medications
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_passcode(input_passcode);
  return query
    select * from public.resident_medications m
     where p_resident_id is null or m.resident_id = p_resident_id
     order by m.resident_id, m.timing;
end;
$$;

-- 服薬の設定(空包確認)。p_resident_id を渡せばその人だけ
create or replace function public.get_med_settings(input_passcode text, p_resident_id uuid default null)
returns setof public.resident_med_settings
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_passcode(input_passcode);
  return query
    select * from public.resident_med_settings s
     where p_resident_id is null or s.resident_id = p_resident_id;
end;
$$;

-- 1 人分のお薬(4 つの時間)と空包確認をまとめて保存する。空の配列 = その時間のお薬なし
create or replace function public.save_medications(
  input_passcode text,
  p_resident_id uuid,
  p_morning text[],
  p_noon text[],
  p_evening text[],
  p_bedtime text[],
  p_empty_check boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_t text;
  v_meds text[];
begin
  perform public.check_passcode(input_passcode);
  if not exists (select 1 from public.residents r where r.id = p_resident_id) then
    raise exception 'この利用者さんが見つかりません';
  end if;

  foreach v_t in array array['morning', 'noon', 'evening', 'bedtime'] loop
    v_meds := case v_t when 'morning' then p_morning when 'noon' then p_noon
                       when 'evening' then p_evening else p_bedtime end;
    if not (coalesce(v_meds, '{}') <@ array['A', 'B', 'C', 'D']) then
      raise exception 'お薬の種類が正しくありません';
    end if;
    -- 重ねず、A から順に
    select coalesce(array_agg(distinct m order by m), '{}') into v_meds from unnest(coalesce(v_meds, '{}')) m;
    insert into public.resident_medications (resident_id, timing, medicines)
    values (p_resident_id, v_t, v_meds)
    on conflict (resident_id, timing) do update set medicines = excluded.medicines;
  end loop;

  insert into public.resident_med_settings (resident_id, empty_check)
  values (p_resident_id, coalesce(p_empty_check, false))
  on conflict (resident_id) do update set empty_check = excluded.empty_check;
end;
$$;

-- ----- 権限(呼べるのは公開キーだけ。中で合言葉を確認する) -----
revoke all on function public.get_medications(text, uuid)                                         from public, anon, authenticated;
revoke all on function public.get_med_settings(text, uuid)                                        from public, anon, authenticated;
revoke all on function public.save_medications(text, uuid, text[], text[], text[], text[], boolean) from public, anon, authenticated;
grant execute on function public.get_medications(text, uuid)                                      to anon;
grant execute on function public.get_med_settings(text, uuid)                                     to anon;
grant execute on function public.save_medications(text, uuid, text[], text[], text[], text[], boolean) to anon;
