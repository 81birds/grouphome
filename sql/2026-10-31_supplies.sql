-- =====================================================
-- 備品管理
--   ・supply_items    … 備品のリスト(使用場所・商品名・種類)。本部が管理する
--       やめた備品は消さずに is_active = false
--   ・supply_requests … 1 行 =「どの施設が・どの備品を・いくつ」本部にお願いしたか
--       status: requested(お願い中)→ ordered(手配済み)→ delivered(届けた)
--       同じ施設・同じ備品の「お願い中」は 1 行だけ(数を直すと書き換え)
--       間違いは void で取り消す(voided_at)
--   ・施設の入力(supplies.html の「施設の入力」)と、本部の管理(「本部の管理」)で使う
-- 方針は 2026-10-10_init.sql と同じ(テーブル直接アクセス不可・関数経由・論理削除)
-- =====================================================

-- ----- 備品のリスト -----
create table if not exists public.supply_items (
  id          uuid primary key default gen_random_uuid(),
  place       text not null check (length(trim(place)) > 0),
  name        text not null check (length(trim(name)) > 0),
  spec        text,
  sort_order  integer not null default 0,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table  public.supply_items            is '備品のリスト';
comment on column public.supply_items.place      is '使用場所(キッチン・おふろ・調味料・食品 など)';
comment on column public.supply_items.name       is '商品名';
comment on column public.supply_items.spec       is '種類・メモ(チューブ・缶詰 など)';
comment on column public.supply_items.sort_order is '並び順(小さいほど上)';
comment on column public.supply_items.is_active  is '使っている備品なら true、やめたら false';

create or replace trigger supply_items_set_updated_at
  before update on public.supply_items
  for each row execute function public.set_updated_at();

alter table public.supply_items enable row level security;
revoke all on public.supply_items from anon, authenticated;

-- ----- 施設からのお願い -----
create table if not exists public.supply_requests (
  id             uuid primary key default gen_random_uuid(),
  house_id       uuid not null references public.houses(id),
  item_id        uuid not null references public.supply_items(id),
  quantity       integer not null check (quantity between 1 and 999),
  status         text not null default 'requested' check (status in ('requested', 'ordered', 'delivered')),
  requested_at   timestamptz not null default now(),
  ordered_at     timestamptz,
  delivered_at   timestamptz,
  voided_at      timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create index if not exists supply_requests_house_idx on public.supply_requests (house_id) where voided_at is null;
create unique index if not exists supply_requests_one_open_idx
  on public.supply_requests (house_id, item_id) where voided_at is null and status = 'requested';

comment on table  public.supply_requests          is '施設から本部への備品のお願い';
comment on column public.supply_requests.quantity is 'ほしい数';
comment on column public.supply_requests.status   is 'requested = お願い中 / ordered = 手配済み / delivered = 届けた';

create or replace trigger supply_requests_set_updated_at
  before update on public.supply_requests
  for each row execute function public.set_updated_at();

alter table public.supply_requests enable row level security;
revoke all on public.supply_requests from anon, authenticated;

-- ----- はじめの備品(リストが空のときだけ入れる) -----
insert into public.supply_items (place, name, spec, sort_order)
select v.place, v.name, v.spec, v.ord * 10
  from (values
    (1,  'キッチン', '食器洗い洗剤', null),
    (2,  'キッチン', 'キッチンペーパー', null),
    (3,  'キッチン', 'サランラップ', null),
    (4,  'おふろ', 'バスマジックリン', null),
    (5,  'おふろ', 'シャンプー', null),
    (6,  'おふろ', 'おふろせっけん', null),
    (7,  'トイレ', 'トイレットペーパー', null),
    (8,  'トイレ', 'トイレクイックル', null),
    (9,  'トイレ', '消臭スプレー', null),
    (10, 'リビング', 'ティッシュペーパー', null),
    (11, 'リビング', 'クイックルシート', null),
    (12, 'リビング', 'L3', null),
    (13, 'オフィス', 'クリアファイル', null),
    (14, 'オフィス', 'ボールペン', null),
    (15, 'オフィス', 'マジック', null),
    (16, 'その他', '蚊取り線香', null),
    (17, 'その他', 'スコップ', null),
    (18, 'その他', '除草剤', null),
    (19, '調味料・食品', '食塩', null),
    (20, '調味料・食品', '砂糖', null),
    (21, '調味料・食品', '穀物酢', null),
    (22, '調味料・食品', 'ごま油', null),
    (23, '調味料・食品', '味噌', null),
    (24, '調味料・食品', 'しょうゆ', null),
    (25, '調味料・食品', 'みりん調味料', null),
    (26, '調味料・食品', '料理酒', null),
    (27, '調味料・食品', 'ケチャップ', null),
    (28, '調味料・食品', 'マヨネーズ', null),
    (29, '調味料・食品', 'ドレッシング', null),
    (30, '調味料・食品', 'オイスターソース', null),
    (31, '調味料・食品', '中濃ソース', null),
    (32, '調味料・食品', 'かつおパック', null),
    (33, '調味料・食品', 'コンソメ', null),
    (34, '調味料・食品', '鶏ガラスープの素', null),
    (35, '調味料・食品', 'からし', 'チューブ'),
    (36, '調味料・食品', 'しょうが', 'チューブ'),
    (37, '調味料・食品', '梅肉', 'チューブ'),
    (38, '調味料・食品', 'めんつゆ', null),
    (39, '調味料・食品', '豆板醤', null),
    (40, '調味料・食品', '甜面醤', null),
    (41, '調味料・食品', 'はちみつ', null),
    (42, '調味料・食品', '小麦粉', null),
    (43, '調味料・食品', 'かたくりこ', null),
    (44, '調味料・食品', 'パン粉', null),
    (45, '調味料・食品', 'スイートコーン', '缶詰'),
    (46, '調味料・食品', 'トマト', '缶詰'),
    (47, '調味料・食品', '塩昆布', null),
    (48, '調味料・食品', 'カットわかめ', null),
    (49, '調味料・食品', 'うどん', null),
    (50, '調味料・食品', 'そば', null),
    (51, '調味料・食品', 'そうめん', null),
    (52, '調味料・食品', '麦茶', null)
  ) as v(ord, place, name, spec)
 where not exists (select 1 from public.supply_items);

-- ----- 備品のリストの関数 -----
-- やめた備品も返す(画面で分ける)
create or replace function public.get_supply_items(input_passcode text)
returns setof public.supply_items
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_passcode(input_passcode);
  return query
    select * from public.supply_items i
     order by i.sort_order, i.created_at;
end;
$$;

-- 備品を足す(同じ使用場所のいちばん下。新しい使用場所ならリストのいちばん下)
create or replace function public.add_supply_item(input_passcode text, p_place text, p_name text, p_spec text default null)
returns public.supply_items
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_place text := trim(coalesce(p_place, ''));
  v_name  text := trim(coalesce(p_name, ''));
  v_order integer;
  v_row   public.supply_items;
begin
  perform public.check_passcode(input_passcode);
  if v_place = '' or v_name = '' then
    raise exception '使用場所と商品名を入れてください';
  end if;
  select max(i.sort_order) into v_order from public.supply_items i where i.place = v_place;
  if v_order is null then
    select max(i.sort_order) into v_order from public.supply_items i;
  end if;
  -- 同じ使用場所の後ろの備品を 1 つずつ下げて、間に入れる
  update public.supply_items i set sort_order = i.sort_order + 1 where i.sort_order > coalesce(v_order, 0);
  insert into public.supply_items (place, name, spec, sort_order)
  values (v_place, v_name, nullif(trim(coalesce(p_spec, '')), ''), coalesce(v_order, 0) + 1)
  returning * into v_row;
  return v_row;
end;
$$;

-- 使用場所・商品名・種類を直す
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
  if p_field in ('place', 'name') and v_value is null then
    raise exception '使用場所と商品名は空にできません';
  end if;
  if p_field = 'place' then
    update public.supply_items set place = v_value where id = p_id;
  elsif p_field = 'name' then
    update public.supply_items set name = v_value where id = p_id;
  elsif p_field = 'spec' then
    update public.supply_items set spec = v_value where id = p_id;
  else
    raise exception '直せない項目です';
  end if;
  if not found then
    raise exception 'この備品が見つかりません';
  end if;
end;
$$;

-- 使うのをやめる / また使う
create or replace function public.set_supply_item_active(input_passcode text, p_id uuid, p_active boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_passcode(input_passcode);
  update public.supply_items set is_active = coalesce(p_active, true) where id = p_id;
  if not found then
    raise exception 'この備品が見つかりません';
  end if;
end;
$$;

-- ----- お願いの関数 -----
-- お願い中・手配済みはすべて、届けたものは p_since 以降の分。p_house_id を渡せばその施設だけ
create or replace function public.get_supply_requests(input_passcode text, p_since date, p_house_id uuid default null)
returns setof public.supply_requests
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_passcode(input_passcode);
  return query
    select * from public.supply_requests r
     where r.voided_at is null
       and (p_house_id is null or r.house_id = p_house_id)
       and (r.status <> 'delivered' or r.delivered_at >= (p_since::timestamp at time zone 'Asia/Tokyo'))
     order by r.requested_at;
end;
$$;

-- 施設のお願いをまとめて保存する。p_items は [{"item_id": "...", "quantity": 2}, ...]
--   お願い中の行があれば数を書き換え、0 なら取り消す。手配済み・届けたものは変えない
create or replace function public.save_supply_requests(input_passcode text, p_house_id uuid, p_items jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_it   jsonb;
  v_item uuid;
  v_qty  integer;
begin
  perform public.check_passcode(input_passcode);
  if not exists (select 1 from public.houses h where h.id = p_house_id and h.is_active) then
    raise exception 'この施設が見つかりません';
  end if;
  if jsonb_typeof(p_items) <> 'array' then
    raise exception 'お願いの形が正しくありません';
  end if;

  for v_it in select * from jsonb_array_elements(p_items) loop
    v_item := (v_it->>'item_id')::uuid;
    v_qty  := coalesce((v_it->>'quantity')::integer, 0);
    if v_qty < 0 or v_qty > 999 then
      raise exception '数は 0〜999 で入れてください';
    end if;
    if v_qty = 0 then
      update public.supply_requests r set voided_at = now()
       where r.house_id = p_house_id and r.item_id = v_item and r.status = 'requested' and r.voided_at is null;
      continue;
    end if;
    if not exists (select 1 from public.supply_items i where i.id = v_item and i.is_active) then
      raise exception '使っていない備品が入っています';
    end if;
    update public.supply_requests r set quantity = v_qty
     where r.house_id = p_house_id and r.item_id = v_item and r.status = 'requested' and r.voided_at is null;
    if not found then
      insert into public.supply_requests (house_id, item_id, quantity) values (p_house_id, v_item, v_qty);
    end if;
  end loop;
end;
$$;

-- 本部: 手配済み・届けたにする(お願い中にもどすこともできる)
create or replace function public.set_supply_request_status(input_passcode text, p_ids uuid[], p_status text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_passcode(input_passcode);
  if p_status not in ('requested', 'ordered', 'delivered') then
    raise exception '状態が正しくありません';
  end if;
  -- お願い中にもどすとき、同じ施設・同じ備品のお願い中がほかにあれば止める(一意の索引で止まる)
  update public.supply_requests r
     set status = p_status,
         ordered_at   = case when p_status = 'requested' then null
                             when p_status = 'ordered' then now()
                             else coalesce(r.ordered_at, now()) end,
         delivered_at = case when p_status = 'delivered' then now() else null end
   where r.id = any(p_ids) and r.voided_at is null;
end;
$$;

-- お願いを取り消す
create or replace function public.void_supply_request(input_passcode text, p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_passcode(input_passcode);
  update public.supply_requests set voided_at = now() where id = p_id and voided_at is null;
  if not found then
    raise exception 'このお願いが見つかりません';
  end if;
end;
$$;

-- ----- 権限(呼べるのは公開キーだけ。中で合言葉を確認する) -----
revoke all on function public.get_supply_items(text)                              from public, anon, authenticated;
revoke all on function public.add_supply_item(text, text, text, text)             from public, anon, authenticated;
revoke all on function public.update_supply_item_field(text, uuid, text, text)    from public, anon, authenticated;
revoke all on function public.set_supply_item_active(text, uuid, boolean)         from public, anon, authenticated;
revoke all on function public.get_supply_requests(text, date, uuid)               from public, anon, authenticated;
revoke all on function public.save_supply_requests(text, uuid, jsonb)             from public, anon, authenticated;
revoke all on function public.set_supply_request_status(text, uuid[], text)       from public, anon, authenticated;
revoke all on function public.void_supply_request(text, uuid)                     from public, anon, authenticated;
grant execute on function public.get_supply_items(text)                           to anon;
grant execute on function public.add_supply_item(text, text, text, text)          to anon;
grant execute on function public.update_supply_item_field(text, uuid, text, text) to anon;
grant execute on function public.set_supply_item_active(text, uuid, boolean)      to anon;
grant execute on function public.get_supply_requests(text, date, uuid)            to anon;
grant execute on function public.save_supply_requests(text, uuid, jsonb)          to anon;
grant execute on function public.set_supply_request_status(text, uuid[], text)    to anon;
grant execute on function public.void_supply_request(text, uuid)                  to anon;
