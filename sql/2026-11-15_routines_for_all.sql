-- =====================================================
-- すべての利用者さんに、基本の日課を入れる(2026-11-15 に実行済み)
--   起床・着がえ 6:30 / バイタル 7:00 / 朝食 7:30 / 通所 8:45(平日)/ 昼食 12:00(土日。平日の昼食はホームにない)
--   通所もどり 16:00(平日)/ 夕食 18:00 / 就寝 21:30(曜日の指定がないものは毎日)
--   服薬は服薬(medication.html)の設定から日課に出るので、ここでは入れない
--   ・同じ種類の日課がすでにある人には入れない(起床・通所・もどり・就寝などは言葉が入っていればあるとみなす)
--   ・つづけて、2026-10-16〜2026-11-14 のこの日課を記録済みにする(バイタルは値がいるので入れない)
--     通所もどりは、その日に「もどり」の記録があれば済み。なければ「もどり」として記録する
-- =====================================================

with base(content, t, w, word, ord) as (
  values ('起床・着がえ', time '06:30', '{}'::smallint[], '起床', 1),
         ('バイタル',     time '07:00', '{}'::smallint[], 'バイタル', 2),
         ('朝食',         time '07:30', '{}'::smallint[], '朝食', 3),
         ('通所',         time '08:45', '{1,2,3,4,5}'::smallint[], '通所', 4),
         ('昼食',         time '12:00', '{0,6}'::smallint[], '昼食', 5),
         ('通所もどり',   time '16:00', '{1,2,3,4,5}'::smallint[], 'もどり', 6),
         ('夕食',         time '18:00', '{}'::smallint[], '夕食', 7),
         ('就寝',         time '21:30', '{}'::smallint[], '就寝', 8)
)
insert into public.resident_routines (resident_id, routine_time, content, weekdays)
select r.id, b.t, b.content, b.w
  from public.residents r cross join base b
 where r.is_active
   and not exists (
     select 1 from public.resident_routines x
      where x.resident_id = r.id and x.is_active
        and x.content like '%' || b.word || '%'
        -- 「通所」は出かけるほう(もどりは別)
        and not (b.word = '通所' and x.content like '%もどり%')
   )
 order by r.id, b.ord;

-- 昨日までの分を記録済みにする
with days as (
  select d::date as d from generate_series(date '2026-10-16', date '2026-11-14', interval '1 day') d
),
people as (
  select dy.d, a.resident_id, rm.house_id
    from days dy
    join public.room_assignments a on a.voided_at is null and a.move_in_date <= dy.d
                                   and (a.move_out_date is null or a.move_out_date > dy.d)
    join public.rooms rm on rm.id = a.room_id
    join public.residents p on p.id = a.resident_id and p.is_active
),
todo as (
  select pp.d, pp.resident_id, pp.house_id, rt.routine_time as t,
         case when rt.content like '%もどり%' then 'もどり' else rt.content end as kind, rt.content
    from people pp
    join public.resident_routines rt on rt.resident_id = pp.resident_id and rt.is_active
     and rt.content <> 'バイタル'
     and (cardinality(rt.weekdays) = 0 or extract(dow from pp.d)::smallint = any (rt.weekdays))
)
insert into public.daily_records (resident_id, house_id, record_date, record_time, kind)
select distinct on (t.resident_id, t.d, t.kind) t.resident_id, t.house_id, t.d, t.t, t.kind
  from todo t
 where not exists (select 1 from public.daily_records x
                    where x.voided_at is null and x.resident_id = t.resident_id and x.record_date = t.d
                      and (x.kind = t.content or x.kind = t.kind))
 order by t.resident_id, t.d, t.kind, t.t;
