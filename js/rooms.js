// =====================================================
// 部屋と入居の共通処理(houses.html / residents.html で使う)
//   読み込み順: common.js のあと
//   入居の期間は [move_in_date, move_out_date)。move_out_date が空なら入居中
// =====================================================
(function () {
  'use strict';

  const R = {
    houses: [], rooms: [], assigns: [], residents: [],

    async load(opts) {
      const want = Object.assign({ houses: true, residents: true }, opts || {});
      const calls = [App.rpc('get_rooms'), App.rpc('get_room_assignments')];
      if (want.houses) calls.push(App.rpc('get_houses'));
      if (want.residents) calls.push(App.rpc('get_residents'));
      const r = await Promise.all(calls);
      R.rooms = r[0]; R.assigns = r[1];
      let i = 2;
      if (want.houses) R.houses = r[i++];
      if (want.residents) R.residents = r[i++];
    },

    today: function () { return App.todayJST(); },

    // その日に有効な入居か
    activeOn: function (a, date) {
      return a.move_in_date <= date && (!a.move_out_date || a.move_out_date > date);
    },

    // 利用者の、その日の入居(なければ null)
    currentOf: function (residentId, date) {
      date = date || R.today();
      return R.assigns.find(function (a) { return a.resident_id === residentId && R.activeOn(a, date); }) || null;
    },

    // 利用者の、これからの入居予定(いちばん近いもの)
    upcomingOf: function (residentId, date) {
      date = date || R.today();
      return R.assigns.filter(function (a) { return a.resident_id === residentId && a.move_in_date > date; })
        .sort(function (a, b) { return a.move_in_date < b.move_in_date ? -1 : 1; })[0] || null;
    },

    // 部屋の、その日の入居(なければ null)
    occupantOf: function (roomId, date) {
      date = date || R.today();
      return R.assigns.find(function (a) { return a.room_id === roomId && R.activeOn(a, date); }) || null;
    },

    // 部屋の、これからの入居予定
    upcomingIn: function (roomId, date) {
      date = date || R.today();
      return R.assigns.filter(function (a) { return a.room_id === roomId && a.move_in_date > date; })
        .sort(function (a, b) { return a.move_in_date < b.move_in_date ? -1 : 1; })[0] || null;
    },

    // その日以降ずっと空いているか(入居日にこの部屋を選べるか)
    freeFrom: function (roomId, date, exceptResidentId) {
      return !R.assigns.some(function (a) {
        return a.room_id === roomId && a.resident_id !== exceptResidentId &&
          (!a.move_out_date || a.move_out_date > date);
      });
    },

    historyOf: function (residentId) {
      return R.assigns.filter(function (a) { return a.resident_id === residentId; })
        .sort(function (a, b) { return a.move_in_date < b.move_in_date ? 1 : -1; });
    },

    roomsOf: function (houseId, includeInactive) {
      return R.rooms.filter(function (r) { return r.house_id === houseId && (includeInactive || r.is_active); })
        .sort(function (a, b) {
          if (a.is_active !== b.is_active) return a.is_active ? -1 : 1;
          return (a.sort_order - b.sort_order) || a.name.localeCompare(b.name, 'ja', { numeric: true });
        });
    },

    byId: function (list, id) { return list.find(function (x) { return x.id === id; }) || null; },
    house: function (id) { return R.byId(R.houses, id); },
    room: function (id) { return R.byId(R.rooms, id); },
    resident: function (id) { return R.byId(R.residents, id); },

    houseShort: function (h) { return h ? (h.short_name || h.name) : '?'; },
    roomName: function (r) { return r ? (/^\d+$/.test(r.name) ? r.name + '号室' : r.name) : '?'; },

    // 「みどり 101号室」
    placeText: function (a, short) {
      if (!a) return '';
      const r = R.room(a.room_id), h = r ? R.house(r.house_id) : null;
      return (short ? R.houseShort(h) : (h ? h.name : '?')) + ' ' + R.roomName(r);
    },

    dateText: function (d) {
      if (!d) return '';
      const p = d.split('-');
      return (+p[0]) + '/' + (+p[1]) + '/' + (+p[2]);
    },

    // 「2026/4/1〜」「2026/4/1〜2026/6/1」
    periodText: function (a) {
      return R.dateText(a.move_in_date) + '〜' + (a.move_out_date ? R.dateText(a.move_out_date) : '');
    },

    // 「101-106」「101,102,201」「101 102」を部屋名の一覧にする
    parseRoomNames: function (text) {
      const out = [];
      String(text || '').normalize('NFKC').split(/[,、\s]+/).forEach(function (part) {
        if (!part) return;
        const m = part.match(/^(\d+)[-〜~](\d+)$/);
        if (m) {
          const a = +m[1], b = +m[2];
          if (b >= a && b - a <= 50) for (let n = a; n <= b; n++) out.push(String(n));
          else out.push(part);
        } else {
          out.push(part);
        }
      });
      return out.filter(function (x, i) { return out.indexOf(x) === i; });
    },

    // DB からのエラーで、そのまま見せてよい説明か
    friendlyError: function (err, fallback) {
      const m = err && err.message ? err.message : '';
      return /入居|部屋|退居|号室|入れてください|直してください|使えません/.test(m) ? m : (fallback || '保存できませんでした');
    },
  };

  window.Rooms = R;
})();
