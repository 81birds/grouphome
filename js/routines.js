// =====================================================
// 利用者さんの日課の共通処理(profile.html・family.html・records.html で使う)
//   お薬(js/meds.js)を読みこんだ画面では、ofDay にお薬も入る
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

    // 起床はかならず 1 日のはじめ、就寝はかならず終わりに並べる(就寝が 0:30 でも最後)
    rank: function (content) {
      const c = String(content || '');
      if (c.indexOf('起床') >= 0) return -1;
      if (c.indexOf('就寝') >= 0) return 1;
      return 0;
    },
    // 内容と時刻で並べる(日課・記録の一覧で使う)
    compare: function (contentA, timeA, contentB, timeB) {
      const d = R.rank(contentA) - R.rank(contentB);
      if (d) return d;
      return timeA < timeB ? -1 : timeA > timeB ? 1 : 0;
    },

    // ある人のその日の日課(時間の順。起床が最初・就寝が最後)
    // meds.js を読みこんだ画面では、お薬(服薬の設定)も日課として混ぜる。
    // opts.staff が false なら、スタッフだけの日課(空包確認)は出さない(利用者さんの画面)
    ofDay: function (residentId, date, opts) {
      const meds = window.Meds ? window.Meds.routinesOf(residentId, opts) : [];
      return R.list.filter(function (r) { return r.resident_id === residentId && R.on(r, date); })
        .concat(meds)
        .sort(function (a, b) { return R.compare(a.content, a.routine_time, b.content, b.routine_time); });
    },
    // id から日課を探す(お薬の日課も)
    find: function (id) {
      return R.list.find(function (r) { return r.id === id; }) || (window.Meds ? window.Meds.findRoutine(id) : null);
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
