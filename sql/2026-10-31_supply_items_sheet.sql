-- =====================================================
-- 備品管理: 施設の備品チェック表(紙のシート 32 品目)の品目を備品リストに足す
--   ・すでにある備品と同じものは足さない
--       食器用洗剤 = 食器洗い洗剤 / キッチンペーパー / ティッシュペーパー / トイレットペーパー
--       クイックルワイパーシート = クイックルシート / お風呂洗剤 = バスマジックリン
--       トイレシート = トイレクイックル
--   ・サランラップは 22cm と 30cm に分ける(今の「サランラップ」は 22cm にする)
--   ・使用場所を足す: 洗面所・洗濯・衛生・ゴミ
--   ・並び順(sort_order)を、使用場所ごとにまとまるように付け直す
--   ・新しい備品には見本の在庫(ダミー)を入れる(在庫の行がまだない備品だけ)
-- =====================================================

-- ----- 新しい備品(同じ名前・種類がまだないときだけ) -----
insert into public.supply_items (place, name, spec, min_stock)
select v.place, v.name, v.spec, v.min_stock
  from (values
    ('キッチン', 'クレンザー',       null,                 1),
    ('キッチン', 'キッチンブリーチ', 'キッチンハイター',   1),
    ('キッチン', 'スポンジ',         null,                 3),
    ('キッチン', '食器用布巾',       '白フェイスタオル',   3),
    ('キッチン', '台布巾',           null,                 3),
    ('キッチン', '排水溝ネット',     null,                 1),
    ('キッチン', 'サランラップ',     '30cm',               1),
    ('キッチン', 'アルミホイル',     null,                 1),
    ('キッチン', 'クッキングシート', null,                 1),
    ('キッチン', 'キッチンポリ袋',   'キッチンパック',     1),
    ('キッチン', 'フリーザーパック', null,                 1),
    ('洗面所',   'ハンドソープ',     null,                 1),
    ('洗面所',   'ペーパータオル',   '茶色',               5),
    ('トイレ',   'トイレ洗剤',       null,                 1),
    ('洗濯',     '洗濯洗剤',         null,                 1),
    ('洗濯',     'ワイドハイター',   null,                 1),
    ('衛生',     'アルコール',       null,                 1),
    ('衛生',     '使い捨て手袋',     'ペラペラの薄いもの', 1),
    ('衛生',     'コットン',         null,                 1),
    ('ゴミ',     'ゴミ袋',           '45L',                1),
    ('ゴミ',     '札幌市ゴミ袋',     '40L',                10),
    ('ゴミ',     '札幌市ゴミ袋',     '20L',                10),
    ('ゴミ',     '札幌市ゴミ袋',     '10L',                10),
    ('ゴミ',     'ビニール袋',       'レジ袋',             1)
  ) as v(place, name, spec, min_stock)
 where not exists (
   select 1 from public.supply_items i
    where i.name = v.name and i.spec is not distinct from v.spec
 );

-- ----- 今のサランラップは 22cm -----
update public.supply_items set spec = '22cm'
 where name = 'サランラップ' and spec is null;

-- ----- 並び順を付け直す(使用場所の順は最初に出てきた順) -----
update public.supply_items i
   set sort_order = v.ord * 10
  from (values
    (1,  '食器洗い洗剤', null), (2, 'クレンザー', null), (3, 'キッチンブリーチ', 'キッチンハイター'),
    (4,  'スポンジ', null), (5, '食器用布巾', '白フェイスタオル'), (6, '台布巾', null), (7, '排水溝ネット', null),
    (8,  'キッチンペーパー', null), (9, 'サランラップ', '22cm'), (10, 'サランラップ', '30cm'),
    (11, 'アルミホイル', null), (12, 'クッキングシート', null), (13, 'キッチンポリ袋', 'キッチンパック'),
    (14, 'フリーザーパック', null),
    (20, 'ハンドソープ', null), (21, 'ペーパータオル', '茶色'),
    (30, 'バスマジックリン', null), (31, 'シャンプー', null), (32, 'おふろせっけん', null),
    (40, 'トイレットペーパー', null), (41, 'トイレ洗剤', null), (42, 'トイレクイックル', null), (43, '消臭スプレー', null),
    (50, '洗濯洗剤', null), (51, 'ワイドハイター', null),
    (60, 'アルコール', null), (61, '使い捨て手袋', 'ペラペラの薄いもの'), (62, 'コットン', null),
    (70, 'ゴミ袋', '45L'), (71, '札幌市ゴミ袋', '40L'), (72, '札幌市ゴミ袋', '20L'), (73, '札幌市ゴミ袋', '10L'),
    (74, 'ビニール袋', 'レジ袋'),
    (80, 'ティッシュペーパー', null), (81, 'クイックルシート', null), (82, 'L3', null),
    (90, 'クリアファイル', null), (91, 'ボールペン', null), (92, 'マジック', null),
    (100, '蚊取り線香', null), (101, 'スコップ', null), (102, '除草剤', null)
  ) as v(ord, name, spec)
 where i.name = v.name
   and i.spec is not distinct from v.spec;

-- 調味料・食品はいちばん下(今の順のまま)
update public.supply_items
   set sort_order = 2000 + sort_order
 where place = '調味料・食品' and sort_order < 2000;

-- ----- 新しい備品の見本の在庫(ダミー。在庫の行がまだない備品だけ) -----
select setseed(0.47);
insert into public.supply_stocks (house_id, item_id, quantity, counted_at)
select h.id, i.id,
       case when random() < 0.2 then floor(random() * i.min_stock)::integer
            else i.min_stock + floor(random() * (i.min_stock + 3))::integer end,
       now() - interval '3 days'
  from public.houses h
 cross join public.supply_items i
 where h.is_active and i.is_active
   and not exists (select 1 from public.supply_stocks s where s.item_id = i.id);
