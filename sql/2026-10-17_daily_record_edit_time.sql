-- =====================================================
-- 日々の記録の編集で、時刻も直せるようにする
--   ・update_daily_record … 1 件の記録の時刻とコメントを書き換える
--   ・update_daily_record_note(コメントだけ)は使わなくなったので、名前を変えて権限を外す
-- 方針は 2026-10-10_init.sql と同じ(関数経由・合言葉の確認)
-- =====================================================

create or replace function public.update_daily_record(input_passcode text, p_id uuid, p_time time, p_note text)
returns public.daily_records
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.daily_records;
begin
  perform public.check_passcode(input_passcode);
  if p_time is null then
    raise exception '時刻を入れてください';
  end if;
  update public.daily_records
     set record_time = p_time,
         note = nullif(trim(p_note), '')
   where id = p_id and voided_at is null
  returning * into v_row;
  if v_row.id is null then
    raise exception 'この記録が見つかりません(取り消された可能性があります)';
  end if;
  return v_row;
end;
$$;

revoke all on function public.update_daily_record(text, uuid, time, text) from public, anon, authenticated;
grant execute on function public.update_daily_record(text, uuid, time, text) to anon;

-- 前の関数は使わない
alter function public.update_daily_record_note(text, uuid, text) rename to update_daily_record_note_unused_20261017;
revoke all on function public.update_daily_record_note_unused_20261017(text, uuid, text) from public, anon, authenticated;
