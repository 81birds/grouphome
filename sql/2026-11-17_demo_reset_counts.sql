-- サンプルデータ: もどした直後の件数を覚えて、開発者の画面ではそれと比べる
--   もどすときに 1 週間前から写して埋めた分も入るので、保存したときの件数とは合わない。
--   画面で「差」として出るのは、もどしたあとに変わったものだけにする

alter table demo.meta add column if not exists restored_counts jsonb;

-- もどして、もどした直後の件数を覚える(pg_cron とボタンはこちらを呼ぶ)
create or replace function demo.restore_and_count(p_by text default 'cron')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r jsonb;
  t text;
  n bigint;
  counts jsonb := '{}'::jsonb;
begin
  r := demo.restore(p_by);
  foreach t in array demo.tables() loop
    execute format('select count(*) from public.%I', t) into n;
    counts := counts || jsonb_build_object(t, n);
  end loop;
  update demo.meta set restored_counts = counts where id = 1;
  return counts || jsonb_build_object('_shift_days', r -> '_shift_days', '_filled_days', r -> '_filled_days');
end;
$$;
revoke all on function demo.restore_and_count(text) from public, anon, authenticated;

create or replace function public.reset_demo_data(input_passcode text)
returns jsonb
language plpgsql
security definer
set search_path = ''
set statement_timeout = '60s'
as $$
begin
  perform public.check_passcode(input_passcode);
  return demo.restore_and_count('button');
end;
$$;

select cron.schedule('demo-restore-daily', '0 18 * * *', $$select demo.restore_and_count('cron')$$);

-- get_demo_info に「もどした直後の件数」を足す(返す列が変わるので、古い関数は名前を変えて使わない)
alter function public.get_demo_info(text) rename to get_demo_info_unused_20261117;
revoke all on function public.get_demo_info_unused_20261117(text) from public, anon, authenticated;

create or replace function public.get_demo_info(input_passcode text)
returns table (table_name text, saved_count integer, restored_count bigint, current_count bigint,
               saved_at timestamptz, restored_at timestamptz, restored_by text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  t text;
  rc jsonb;
begin
  perform public.check_passcode(input_passcode);
  select m.restored_at, m.restored_by, m.restored_counts into restored_at, restored_by, rc from demo.meta m where m.id = 1;
  foreach t in array demo.tables() loop
    table_name := t;
    saved_count := null;
    saved_at := null;
    select s.row_count, s.saved_at into saved_count, saved_at from demo.snapshots s where s.table_name = t;
    restored_count := (rc ->> t)::bigint;
    execute format('select count(*) from public.%I', t) into current_count;
    return next;
  end loop;
end;
$$;
revoke all on function public.get_demo_info(text) from public, anon, authenticated;
grant execute on function public.get_demo_info(text) to anon;

-- いまの件数を「もどした直後の件数」として入れておく(15:08 にボタンでもどしたまま)
update demo.meta m set restored_counts = (
  select jsonb_object_agg(t, (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from public.%I', t), false, true, '')))[1]::text::bigint)
  from unnest(demo.tables()) t
) where m.id = 1;
