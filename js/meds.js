// =====================================================
// 服薬の共通処理(medication.html・records.html・family.html で使う)
//   読み込み順: common.js のあと
//   DB は resident_medications(timing・medicines)と resident_med_settings(empty_check)
//   お薬は日課と同じ形(routine_time・content)にして、Routines.ofDay に混ぜて出す
// =====================================================
(function () {
  'use strict';

  // お薬の時間。time は日課に出すときの時刻、note は空包確認の記録に入れる文
  const TIMINGS = [
    { key: 'morning', label: '朝',     name: '朝のお薬',     time: '07:30', note: '朝食前後薬 確認' },
    { key: 'noon',    label: '昼',     name: '昼のお薬',     time: '12:30', note: '昼食前後薬 確認' },
    { key: 'evening', label: '夕',     name: '夕のお薬',     time: '18:30', note: '夕食前後薬 確認' },
    { key: 'bedtime', label: '寝る前', name: '寝る前のお薬', time: '20:30', note: '就寝薬 確認' },
  ];
  const MEDICINES = ['A', 'B', 'C', 'D'];
  // 空包確認(スタッフの日課)。1 日 1 回、最後のお薬のあと。名前は日々の記録の内容のチップと同じ
  const CHECK = { name: 'お薬空包確認', time: '21:00' };

  const M = {
    TIMINGS: TIMINGS,
    MEDICINES: MEDICINES,
    CHECK: CHECK,
    list: [],       // resident_medications
    settings: [],   // resident_med_settings

    // p_resident_id を渡せばその人だけ。読めなくてもほかの画面は動くように、失敗したら空にする
    async load(residentId) {
      const args = residentId ? { p_resident_id: residentId } : {};
      try {
        const r = await Promise.all([App.rpc('get_medications', args), App.rpc('get_med_settings', args)]);
        M.list = r[0]; M.settings = r[1];
      } catch (err) {
        console.error(err);
        M.list = []; M.settings = [];
        throw err;
      }
    },

    // その人のお薬 { morning: ['A', 'C'], noon: [], ... }
    of: function (residentId) {
      const out = {};
      TIMINGS.forEach(function (t) { out[t.key] = []; });
      M.list.forEach(function (m) {
        if (m.resident_id === residentId && out[m.timing]) out[m.timing] = (m.medicines || []).slice();
      });
      return out;
    },
    has: function (residentId) {
      const o = M.of(residentId);
      return TIMINGS.some(function (t) { return o[t.key].length > 0; });
    },
    emptyCheck: function (residentId) {
      const s = M.settings.find(function (x) { return x.resident_id === residentId; });
      return !!(s && s.empty_check);
    },

    // 「朝のお薬(A・C)」
    content: function (t, meds) { return t.name + '(' + meds.join('・') + ')'; },
    medsText: function (meds) { return meds && meds.length ? meds.join('・') : ''; },

    // 日課の形にしたお薬(と空包確認)。opts.staff が false なら空包確認は出さない(利用者さんの画面)
    routinesOf: function (residentId, opts) {
      const staff = !opts || opts.staff !== false;
      const o = M.of(residentId);
      const out = [];
      TIMINGS.forEach(function (t) {
        if (!o[t.key].length) return;
        out.push({ id: 'med:' + residentId + ':' + t.key, resident_id: residentId, routine_time: t.time + ':00',
          content: M.content(t, o[t.key]), med: true });
      });
      if (staff && out.length && M.emptyCheck(residentId)) {
        // 記録に入れる文は、その人のお薬の時間だけ
        const note = TIMINGS.filter(function (t) { return o[t.key].length; }).map(function (t) { return t.note; }).join('\n');
        out.push({ id: 'med:' + residentId + ':check', resident_id: residentId, routine_time: CHECK.time + ':00',
          content: CHECK.name, note: note, med: true, staffOnly: true });
      }
      return out;
    },
    // id から探す('med:<resident_id>:<morning / check>')
    findRoutine: function (id) {
      const p = String(id || '').split(':');
      if (p[0] !== 'med' || p.length !== 3) return null;
      return M.routinesOf(p[1]).find(function (r) { return r.id === id; }) || null;
    },
    // 記録の内容がお薬の日課から入れたものか(アイコン用)
    isMedContent: function (content) {
      return TIMINGS.some(function (t) { return String(content || '').indexOf(t.name + '(') === 0; });
    },
  };

  window.Meds = M;
})();
