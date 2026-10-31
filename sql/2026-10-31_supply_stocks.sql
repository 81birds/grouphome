-- =====================================================
-- 備品管理: 在庫と「使った」の記録
--   ・supply_items.min_stock … 最低ストック基準(全施設で同じ)。在庫がこれより少ないと「足りない」
--   ・supply_stocks … 1 行 =「どの施設に・どの備品が・いくつあるか」(施設 × 備品で 1 行)
--   ・supply_usages … 「使った」ボタンを押した記録。1 回 = 1 つ。押すと在庫が 1 減る
--       間違いは void_supply_usage で取り消す(voided_at。在庫は 1 もどる)
--   ・本部が「届けた」にすると、その数だけ施設の在庫が増える(もどすと減る)
--   ・最後に、試作の見本の在庫(ダミー)を入れる。在庫が空のときだけ
-- 方針は 2026-10-10_init.sql と同じ(テーブル直接アクセス不可・関数経由・論理削除)
-- =====================================================

-- ----- 最低ストック基準 -----
alter table public.supply_items
  add column if not exists min_stock integer not null default 1 check (min_stock between 0 and 999);

comment on column public.supply_items.min_stock is '最低ストック基準(在庫がこれより少ないと足りない)';

-- ----- 在庫 -----
create table if not exists public.supply_stocks (
  id          uuid primary key default gen_random_uuid(),
  house_id    uuid not null references public.houses(id),
  item_id     uuid not null references public.supply_items(id),
  quantity    integer not null default 0 check (quantity between 0 and 9999),
  counted_at  timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (house_id, item_id)
);

comment on table  public.supply_stocks            is '施設ごとの備品の在庫';
comment on column public.supply_stocks.quantity   is 'いまある数';
comment on column public.supply_stocks.counted_at is '最後に数を数えて直した日時';

create or replace trigger supply_stocks_set_updated_at
  before update on public.supply_stocks
  for each row execute function public.set_updated_at();

alter table public.supply_stocks enable row level security;
revoke all on public.supply_stocks from anon, authenticated;

-- ----- 使った記録 -----
create table if not exists public.supply_usages (
  id          uuid primary key default gen_random_uuid(),
  house_id    uuid not null references public.houses(id),
  item_id     uuid not null references public.supply_items(id),
  quantity    integer not null default 1 check (quantity > 0),
  used_at     timestamptz not null default now(),
  voided_at   timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists supply_usages_house_idx on public.supply_usages (house_id, used_at) where voided_at is null;

comment on table public.supply_usages is '備品を使った記録(「使った」ボタン 1 回 = 1 つ)';

create or replace trigger supply_usages_set_updated_at
  before update on public.supply_usages
  for each row execute function public.set_updated_at();

alter table public.supply_usages enable row level security;
revoke all on public.supply_usages from anon, authenticated;

-- ----- 関数 -----
-- 在庫。p_house_id を渡せばその施設だけ
create or replace function public.get_supply_stocks(input_passcode text, p_house_id uuid default null)
returns setof public.supply_stocks
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_passcode(input_passcode);
  return query
    select * from public.supply_stocks s
     where p_house_id is null or s.house_id = p_house_id;
end;
$$;

-- 在庫の数を数えて直す
create or replace function public.set_supply_stock(input_passcode text, p_house_id uuid, p_item_id uuid, p_quantity integer)
returns public.supply_stocks
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.supply_stocks;
begin
  perform public.check_passcode(input_passcode);
  if p_quantity is null or p_quantity < 0 or p_quantity > 9999 then
    raise exception '在庫の数は 0〜9999 で入れてください';
  end if;
  if not exists (select 1 from public.houses h where h.id = p_house_id) then
    raise exception 'この施設が見つかりません';
  end if;
  if not exists (select 1 from public.supply_items i where i.id = p_item_id) then
    raise exception 'この備品が見つかりません';
  end if;
  insert into public.supply_stocks (house_id, item_id, quantity, counted_at)
  values (p_house_id, p_item_id, p_quantity, now())
  on conflict (house_id, item_id) do update set quantity = excluded.quantity, counted_at = excluded.counted_at
  returning * into v_row;
  return v_row;
end;
$$;

-- 使った記録(届けたものと同じく p_since 以降)
create or replace function public.get_supply_usages(input_passcode text, p_since date, p_house_id uuid default null)
returns setof public.supply_usages
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_passcode(input_passcode);
  return query
    select * from public.supply_usages u
     where u.voided_at is null
       and u.used_at >= (p_since::timestamp at time zone 'Asia/Tokyo')
       and (p_house_id is null or u.house_id = p_house_id)
     order by u.used_at;
end;
$$;

-- 1 つ使った。在庫を 1 減らし、記録を残す
create or replace function public.use_supply(input_passcode text, p_house_id uuid, p_item_id uuid)
returns public.supply_usages
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.supply_usages;
begin
  perform public.check_passcode(input_passcode);
  update public.supply_stocks s set quantity = s.quantity - 1
   where s.house_id = p_house_id and s.item_id = p_item_id and s.quantity > 0;
  if not found then
    raise exception '在庫が 0 です。在庫の数を直してから押してください';
  end if;
  insert into public.supply_usages (house_id, item_id) values (p_house_id, p_item_id)
  returning * into v_row;
  return v_row;
end;
$$;

-- 使った記録を取り消す(在庫をもどす)
create or replace function public.void_supply_usage(input_passcode text, p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.supply_usages;
begin
  perform public.check_passcode(input_passcode);
  update public.supply_usages set voided_at = now() where id = p_id and voided_at is null
  returning * into v_row;
  if not found then
    raise exception 'この記録が見つかりません';
  end if;
  insert into public.supply_stocks (house_id, item_id, quantity)
  values (v_row.house_id, v_row.item_id, v_row.quantity)
  on conflict (house_id, item_id) do update set quantity = public.supply_stocks.quantity + excluded.quantity;
end;
$$;

-- 備品の項目に最低ストック基準(min_stock)を足す(引数は前と同じ)
create or replace function public.update_supply_item_field(input_passcode text, p_id uuid, p_field text, p_value text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_value text := nullif(trim(coalesce(p_value, '')), '');
begin
  perform public.check_passcode(input_passcode);
  if p_field in ('place', 'name', 'min_stock') and v_value is null then
    raise exception '使用場所・商品名・最低ストック基準は空にできません';
  end if;
  if p_field = 'place' then
    update public.supply_items set place = v_value where id = p_id;
  elsif p_field = 'name' then
    update public.supply_items set name = v_value where id = p_id;
  elsif p_field = 'spec' then
    update public.supply_items set spec = v_value where id = p_id;
  elsif p_field = 'min_stock' then
    if v_value !~ '^[0-9]{1,3}$' then
      raise exception '最低ストック基準は 0〜999 の数で入れてください';
    end if;
    update public.supply_items set min_stock = v_value::integer where id = p_id;
  else
    raise exception '直せない項目です';
  end if;
  if not found then
    raise exception 'この備品が見つかりません';
  end if;
end;
$$;

-- 「届けた」にすると施設の在庫を増やし、届けたからもどすと減らす(引数は前と同じ)
create or replace function public.set_supply_request_status(input_passcode text, p_ids uuid[], p_status text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req public.supply_requests;
begin
  perform public.check_passcode(input_passcode);
  if p_status not in ('requested', 'ordered', 'delivered') then
    raise exception '状態が正しくありません';
  end if;
  for v_req in
    select * from public.supply_requests r where r.id = any(p_ids) and r.voided_at is null and r.status <> p_status
  loop
    if p_status = 'delivered' then
      insert into public.supply_stocks (house_id, item_id, quantity)
      values (v_req.house_id, v_req.item_id, v_req.quantity)
      on conflict (house_id, item_id) do update set quantity = public.supply_stocks.quantity + excluded.quantity;
    elsif v_req.status = 'delivered' then
      update public.supply_stocks s set quantity = greatest(s.quantity - v_req.quantity, 0)
       where s.house_id = v_req.house_id and s.item_id = v_req.item_id;
    end if;
    -- お願い中にもどすとき、同じ施設・同じ備品のお願い中がほかにあれば止める(一意の索引で止まる)
    update public.supply_requests r
       set status = p_status,
           ordered_at   = case when p_status = 'requested' then null
                               when p_status = 'ordered' then now()
                               else coalesce(r.ordered_at, now()) end,
           delivered_at = case when p_status = 'delivered' then now() else null end
     where r.id = v_req.id;
  end loop;
end;
$$;

-- ----- 権限(呼べるのは公開キーだけ。中で合言葉を確認する) -----
revoke all on function public.get_supply_stocks(text, uuid)                   from public, anon, authenticated;
revoke all on function public.set_supply_stock(text, uuid, uuid, integer)     from public, anon, authenticated;
revoke all on function public.get_supply_usages(text, date, uuid)             from public, anon, authenticated;
revoke all on function public.use_supply(text, uuid, uuid)                    from public, anon, authenticated;
revoke all on function public.void_supply_usage(text, uuid)                   from public, anon, authenticated;
grant execute on function public.get_supply_stocks(text, uuid)                to anon;
grant execute on function public.set_supply_stock(text, uuid, uuid, integer)  to anon;
grant execute on function public.get_supply_usages(text, date, uuid)          to anon;
grant execute on function public.use_supply(text, uuid, uuid)                 to anon;
grant execute on function public.void_supply_usage(text, uuid)                to anon;

-- ----- 最低ストック基準(見本の値。本部の「備品リスト」で直せる) -----
update public.supply_items i set min_stock = v.min_stock
  from (values
    ('食器洗い洗剤', 2), ('キッチンペーパー', 4), ('サランラップ', 2),
    ('バスマジックリン', 1), ('シャンプー', 2), ('おふろせっけん', 3),
    ('トイレットペーパー', 12), ('トイレクイックル', 2), ('消臭スプレー', 2),
    ('ティッシュペーパー', 5), ('クイックルシート', 2), ('L3', 1),
    ('クリアファイル', 10), ('ボールペン', 5), ('マジック', 3),
    ('蚊取り線香', 1), ('スコップ', 1), ('除草剤', 1),
    ('食塩', 1), ('砂糖', 1), ('穀物酢', 1), ('ごま油', 1), ('味噌', 2), ('しょうゆ', 2),
    ('みりん調味料', 1), ('料理酒', 1), ('ケチャップ', 1), ('マヨネーズ', 2), ('ドレッシング', 2),
    ('オイスターソース', 1), ('中濃ソース', 1), ('かつおパック', 2), ('コンソメ', 1), ('鶏ガラスープの素', 1),
    ('からし', 1), ('しょうが', 1), ('梅肉', 1), ('めんつゆ', 2), ('豆板醤', 1), ('甜面醤', 1),
    ('はちみつ', 1), ('小麦粉', 1), ('かたくりこ', 1), ('パン粉', 1),
    ('スイートコーン', 3), ('トマト', 3), ('塩昆布', 1), ('カットわかめ', 1),
    ('うどん', 5), ('そば', 3), ('そうめん', 3), ('麦茶', 2)
  ) as v(name, min_stock)
 where i.name = v.name;

-- ----- 見本の在庫(ダミー。在庫が空のときだけ) -----
--   おおむね基準より少し多め。2 割ほどは基準より少なくする
select setseed(0.31);
insert into public.supply_stocks (house_id, item_id, quantity, counted_at)
select h.id, i.id,
       case when random() < 0.2 then floor(random() * i.min_stock)::integer
            else i.min_stock + floor(random() * (i.min_stock + 3))::integer end,
       now() - interval '3 days'
  from public.houses h
 cross join public.supply_items i
 where h.is_active and i.is_active
   and not exists (select 1 from public.supply_stocks);
