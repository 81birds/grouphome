// =====================================================
// 食事の予定の共通処理(family.html・meals.html で使う)
//   読み込み順: common.js のあと
//   土日は朝・昼・夕の 3 食、平日は朝と夕(昼はない)
//   DB は meal_plans(will_eat: true = ○ 食べる / false = × 食べない / 行なし = 未回答)
// =====================================================
(function () {
  'use strict';

  const DOW = ['日', '月', '火', '水', '木', '金', '土'];

  const M = {
    KINDS: [
      { key: 'breakfast', label: '朝食', short: '朝', icon: 'ti-sunrise' },
      { key: 'lunch',     label: '昼食', short: '昼', icon: 'ti-sun' },
      { key: 'dinner',    label: '夕食', short: '夕', icon: 'ti-moon' },
    ],

    dow: function (date) { return new Date(date + 'T00:00:00Z').getUTCDay(); },
    isWeekend: function (date) { const w = M.dow(date); return w === 0 || w === 6; },
    // その日にある食事か(平日の昼はない)
    hasMeal: function (date, key) { return key !== 'lunch' || M.isWeekend(date); },

    addDays: function (date, n) {
      const d = new Date(date + 'T00:00:00Z');
      d.setUTCDate(d.getUTCDate() + n);
      return d.toISOString().slice(0, 10);
    },
    // 10/18(土)
    dateLabel: function (date) { return (+date.slice(5, 7)) + '/' + (+date.slice(8, 10)) + '(' + DOW[M.dow(date)] + ')'; },
    // 土曜・日曜の色分け用の class
    dayClass: function (date) { const w = M.dow(date); return w === 0 ? 'sun' : w === 6 ? 'sat' : ''; },

    // plans(配列)を「利用者さん|日付|食事」→ will_eat の表にする
    index: function (plans) {
      const map = {};
      (plans || []).forEach(function (p) { map[p.resident_id + '|' + p.meal_date + '|' + p.meal] = p.will_eat; });
      return map;
    },
    // 同じ形で「誰が選んだか」(resident / staff)
    byIndex: function (plans) {
      const map = {};
      (plans || []).forEach(function (p) { map[p.resident_id + '|' + p.meal_date + '|' + p.meal] = p.set_by || 'resident'; });
      return map;
    },
    key: function (residentId, date, meal) { return residentId + '|' + date + '|' + meal; },

    // ○ / × / 未 の表示
    mark: function (v) { return v === true ? '○' : v === false ? '×' : '未'; },
    markClass: function (v) { return v === true ? 'eat' : v === false ? 'skip' : 'unset'; },
    // 背景の色分けまで含めた class(スタッフが変えたものは by-staff)
    cellClass: function (v, by) { return M.markClass(v) + (v !== undefined && by === 'staff' ? ' by-staff' : ''); },
  };

  window.Meals = M;
})();
