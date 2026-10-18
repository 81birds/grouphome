// =====================================================
// 利用者さんの日課の共通処理(profile.html・family.html・records.html で使う)
//   読み込み順: common.js のあと
//   DB は resident_routines(routine_time・content・weekdays)。weekdays は 0 = 日 … 6 = 土、空なら毎日
// =====================================================
(function () {
  'use strict';

  const DOW = ['日', '月', '火', '水', '木', '金', '土'];

  const R = {
    DOW: DOW,
    list: [],

    // p_resident_id を渡せばその人だけ
    async load(residentId) {
      R.list = await App.rpc('get_routines', residentId ? { p_resident_id: residentId } : {});
      return R.list;
    },

    time: function (t) { return t ? String(t).slice(0, 5) : ''; },

    // その日にある日課か
    on: function (r, date) {
      if (!r.weekdays || !r.weekdays.length) return true;
      const w = new Date(date + 'T00:00:00Z').getUTCDay();
      return r.weekdays.indexOf(w) >= 0;
    },

    // ある人のその日の日課(時間の順)
    ofDay: function (residentId, date) {
      return R.list.filter(function (r) { return r.resident_id === residentId && R.on(r, date); })
        .sort(function (a, b) { return a.routine_time < b.routine_time ? -1 : a.routine_time > b.routine_time ? 1 : 0; });
    },

    // 「毎日」「平日」「土日」「月・水・金」
    daysText: function (days) {
      if (!days || !days.length || days.length === 7) return '毎日';
      const s = days.slice().sort().join(',');
      if (s === '1,2,3,4,5') return '平日';
      if (s === '0,6') return '土日';
      return days.slice().sort().map(function (d) { return DOW[d]; }).join('・');
    },
  };

  window.Routines = R;
})();
