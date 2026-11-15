-- =====================================================
-- 服薬のサンプル(ダミー)データ。2026-11-15_medications.sql のあとに 1 回だけ実行する
--   ・いま入居している利用者さんの約 7 割がお薬あり
--   ・お薬ありの人のうち、約 2 割が朝・昼・夕、ほかは昼・夕だけ
--   ・お薬ありの人のうち、約 2 割は寝る前のお薬もある
--   ・お薬の種類(A〜D)は、時間ごとに 1〜2 種類をランダムに入れる(id から決めるので、何回実行しても同じ)
--   ・お薬ありの人は、空包確認をスタッフの日課に入れる
--   ・すでに設定がある人は変えない(on conflict do nothing)
-- =====================================================

with base as (
  select r.id,
         row_number() over (order by md5(r.id::text)) as rn,
         count(*) over () as n
    from public.residents r
   where r.is_active
     and exists (select 1 from public.room_assignments a
                  where a.resident_id = r.id and a.voided_at is null
                    and a.move_in_date <= current_date
                    and (a.move_out_date is null or a.move_out_date > current_date))
),
med as (
  select b.id,
         row_number() over (order by md5(b.id::text || 'three')) as i3,
         row_number() over (order by md5(b.id::text || 'bed')) as ib,
         count(*) over () as m
    from base b
   where b.rn <= round(b.n * 0.7)
),
plan as (
  select id, (i3 <= round(m * 0.2)) as three, (ib <= round(m * 0.2)) as bed from med
),
rows as (
  select p.id, t.timing,
         decode(md5(p.id::text || t.timing), 'hex') as h
    from plan p
   cross join (values ('morning'), ('noon'), ('evening'), ('bedtime')) as t(timing)
   where t.timing in ('noon', 'evening')
      or (t.timing = 'morning' and p.three)
      or (t.timing = 'bedtime' and p.bed)
),
ins_meds as (
  insert into public.resident_medications (resident_id, timing, medicines)
  select r.id, r.timing,
         (select array_agg(distinct x order by x)
            from unnest(array[
              (array['A', 'B', 'C', 'D'])[get_byte(r.h, 0) % 4 + 1],
              case when get_byte(r.h, 2) % 2 = 0 then (array['A', 'B', 'C', 'D'])[get_byte(r.h, 1) % 4 + 1] end
            ]) x where x is not null)
    from rows r
  on conflict (resident_id, timing) do nothing
  returning resident_id
)
insert into public.resident_med_settings (resident_id, empty_check)
select p.id, true from plan p
on conflict (resident_id) do nothing;
