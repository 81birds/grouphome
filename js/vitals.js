// =====================================================
// バイタルの共通処理(family.html・vitals.html で使う)
//   読み込み順: common.js のあと
//   DB は vitals(体温・血圧の上下・脈拍・前日の入浴 bath / shower)
//   注意の目安(赤で出す)はここで決める。医療の判断ではなく、気づくための目安
// =====================================================
(function () {
  'use strict';

  const V = {
    BATH: { bath: 'お風呂', shower: 'シャワー' },

    // 注意の目安
    LIMITS: {
      temperature: { low: 35.5, high: 37.5 },   // 37.5 以上は発熱
      bp_high:     { low: 90,   high: 140 },
      bp_low:      { low: 50,   high: 90 },
      pulse:       { low: 50,   high: 100 },
    },
    // 目安を外れていれば true
    alert: function (field, value) {
      if (value === null || value === undefined || value === '') return false;
      const l = V.LIMITS[field], n = Number(value);
      return n < l.low || n >= l.high;
    },

    time: function (t) { return t ? String(t).slice(0, 5) : ''; },
    temp: function (v) { return v === null || v === undefined ? '' : Number(v).toFixed(1) + '℃'; },
    bp: function (r) { return r.bp_high ? r.bp_high + '/' + r.bp_low : ''; },
    pulse: function (v) { return v ? v + '回/分' : ''; },
    bath: function (v) { return v ? V.BATH[v] || '' : ''; },
  };

  window.Vitals = V;
})();
