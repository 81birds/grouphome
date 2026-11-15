-- =====================================================
-- 前から入っていた「お薬空包確認」の記録を取り消す(2026-11-15 に実行済み・1,224 件 + 533 件)
--   ・服薬(2026-11-15_medications.sql)で、空包確認はスタッフの日課になった
--   ・その前に、日課ではなく記録として入れていた空包確認が、日課のものとだぶるため
--   ・対象は、空包確認の日課がある人(resident_med_settings.empty_check)の、2026-11-15 より前に入れた記録
--   ・消さずに voided_at を入れる(もどすときは voided_at を null にする)
-- =====================================================

update public.daily_records d
   set voided_at = now()
 where d.voided_at is null
   and d.kind = 'お薬空包確認'
   and d.created_at < timestamptz '2026-11-15 00:00:00+09'
   and exists (select 1 from public.resident_med_settings s where s.resident_id = d.resident_id and s.empty_check);

-- つづけて、空包確認の日課がない人の分も、まちがいとして取り消した(533 件)
update public.daily_records d
   set voided_at = now()
 where d.voided_at is null
   and d.kind = 'お薬空包確認'
   and d.created_at < timestamptz '2026-11-15 00:00:00+09';
