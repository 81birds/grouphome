-- =====================================================
-- 日々の記録にコメントを付ける
--   ・daily_records.note(もともとある列)を、記録ごとのコメントとして使う
--   ・update_daily_record_note … 1 件の記録のコメントを書き換える(空なら null)
-- 方針は 2026-10-10_init.sql と同じ(関数経由・合言葉の確認)
-- =====================================================

comment on column public.daily_records.note is '記録ごとのコメント';

create or replace function public.update_daily_record_note(input_passcode text, p_id uuid, p_note text)
returns public.daily_records
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.daily_records;
begin
  perform public.check_passcode(input_passcode);
  update public.daily_records
     set note = nullif(trim(p_note), '')
   where id = p_id and voided_at is null
  returning * into v_row;
  if v_row.id is null then
    raise exception 'この記録が見つかりません(取り消された可能性があります)';
  end if;
  return v_row;
end;
$$;

revoke all on function public.update_daily_record_note(text, uuid, text) from public, anon, authenticated;
grant execute on function public.update_daily_record_note(text, uuid, text) to anon;
