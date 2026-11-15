-- =====================================================
-- サンプルデータの整理(2026-11-15 に実行済み)
--   1. 明日(2026-11-16)以降の記録・バイタルを取り消す(voided_at)
--      → 日課は、記録がなければ日々の記録の「きょうの日課」にもどる
--   2. 2026-10-16〜2026-11-14 の日課(お薬・空包確認も)を記録済みにする
--      ・その日に入居している人の、その日の曜日の日課で、同じ内容の記録がまだないもの
--      ・お薬は服薬の設定から(内容・時刻は js/meds.js の TIMINGS と同じ)
--      ・空包確認はお薬の記録より後に入れたことにする(created_at を 1 秒あと)
--   3. 2026-12-01〜2026-12-31 のシフトを入れる
--      ・ハウスごとに、所属スタッフ(名前の読みの順)で順番に、毎日 日勤 1 人・夜勤 1 人、土日は遅番も 1 人
--      ・夜勤の翌日は日勤に入らない並び(日勤は 2 つ先の人)
-- =====================================================

-- ----- 1. 明日以降の記録・バイタルを取り消す -----
update public.daily_records set voided_at = now()
 where voided_at is null and record_date >= date '2026-11-16';
update public.vitals set voided_at = now()
 where voided_at is null and measured_date >= date '2026-11-16';

-- ----- 2. 昨日までの日課を記録済みにする -----
with days as (
  select d::date as d from generate_series(date '2026-10-16', date '2026-11-14', interval '1 day') d
),
people as (
  select dy.d, a.resident_id, r.house_id
    from days dy
    join public.room_assignments a on a.voided_at is null and a.move_in_date <= dy.d
                                   and (a.move_out_date is null or a.move_out_date > dy.d)
    join public.rooms r on r.id = a.room_id
    join public.residents p on p.id = a.resident_id and p.is_active
),
timings(timing, name, t, note, ord) as (
  values ('morning', '朝のお薬', time '07:30', '朝食前後薬 確認', 1),
         ('noon', '昼のお薬', time '12:30', '昼食前後薬 確認', 2),
         ('evening', '夕のお薬', time '18:30', '夕食前後薬 確認', 3),
         ('bedtime', '寝る前のお薬', time '20:30', '就寝薬 確認', 4)
),
todo as (
  -- 日課
  select pp.d, pp.resident_id, pp.house_id, rt.routine_time as t, rt.content as kind, null::text as note, now() as created
    from people pp
    join public.resident_routines rt on rt.resident_id = pp.resident_id and rt.is_active
     and (cardinality(rt.weekdays) = 0 or extract(dow from pp.d)::smallint = any (rt.weekdays))
  union all
  -- お薬
  select pp.d, pp.resident_id, pp.house_id, tm.t, tm.name || '(' || array_to_string(m.medicines, '・') || ')', null, now()
    from people pp
    join public.resident_medications m on m.resident_id = pp.resident_id and cardinality(m.medicines) > 0
    join timings tm on tm.timing = m.timing
  union all
  -- 空包確認(お薬の記録より後に入れたことにする)
  select pp.d, pp.resident_id, pp.house_id, time '21:00', 'お薬空包確認',
         (select string_agg(tm.note, E'\n' order by tm.ord)
            from public.resident_medications m join timings tm on tm.timing = m.timing
           where m.resident_id = pp.resident_id and cardinality(m.medicines) > 0),
         now() + interval '1 second'
    from people pp
    join public.resident_med_settings s on s.resident_id = pp.resident_id and s.empty_check
   where exists (select 1 from public.resident_medications m where m.resident_id = pp.resident_id and cardinality(m.medicines) > 0)
)
insert into public.daily_records (resident_id, house_id, record_date, record_time, kind, note, created_at)
select distinct on (t.resident_id, t.d, t.kind) t.resident_id, t.house_id, t.d, t.t, t.kind, t.note, t.created
  from todo t
 where not exists (select 1 from public.daily_records x
                    where x.voided_at is null and x.resident_id = t.resident_id
                      and x.record_date = t.d and x.kind = t.kind)
 order by t.resident_id, t.d, t.kind, t.t;

-- ----- 3. 12 月のシフト -----
with st as (
  select s.id, s.house_id,
         row_number() over (partition by s.house_id order by s.kana nulls last, s.name, s.id) - 1 as i,
         count(*) over (partition by s.house_id) as n
    from public.staff s
    join public.houses h on h.id = s.house_id and h.is_active
   where s.is_active
),
days as (
  select d::date as d, (d::date - date '2026-12-01') as k
    from generate_series(date '2026-12-01', date '2026-12-31', interval '1 day') d
),
types as (
  select name, id, start_time, end_time from public.shift_types where is_active and name in ('日勤', '夜勤', '遅番')
),
plan as (
  select dy.d, s.house_id, s.id as staff_id,
         case when s.i = dy.k % s.n then '夜勤'
              when s.i = (dy.k + 2) % s.n then '日勤'
              when s.i = (dy.k + 1) % s.n and extract(dow from dy.d) in (0, 6) then '遅番' end as type_name
    from days dy cross join st s
   where s.n >= 4
)
insert into public.shifts (work_date, staff_id, house_id, shift_type_id, start_time, end_time)
select p.d, p.staff_id, p.house_id, t.id, t.start_time, t.end_time
  from plan p join types t on t.name = p.type_name
 where not exists (select 1 from public.shifts x
                    where x.voided_at is null and x.work_date = p.d and x.house_id = p.house_id and x.shift_type_id = t.id);
