// =====================================================
// 本日のスタッフ(その日・その施設の勤務を、0〜24 時の帯で出す)
//   records.html・family.html で使う。読み込み順: common.js のあと
//   前日に始まった夜勤も含める(get_shifts は前日分も返す)
//   見た目は common.css の .tl-*
// =====================================================
(function () {
  'use strict';

  const DAY = 24 * 60;
  function hm(t) { return t ? String(t).slice(0, 5) : ''; }
  function minOf(t) { const p = hm(t).split(':'); return (+p[0]) * 60 + (+p[1]); }
  function crosses(s) { return minOf(s.end_time) <= minOf(s.start_time); }
  function durationOf(s) { let d = minOf(s.end_time) - minOf(s.start_time); if (d <= 0) d += DAY; return d; }
  function shiftText(s) { return hm(s.start_time) + '〜' + (crosses(s) ? '翌' : '') + hm(s.end_time); }
  function dayOffset(workDate, date) { return Math.round((new Date(workDate + 'T00:00:00Z') - new Date(date + 'T00:00:00Z')) / 86400000); }

  const S = {
    staff: [], types: [], shifts: [], date: null,

    // スタッフと勤務区分(名前・夜勤かどうかに使う)
    async loadMasters() {
      const r = await Promise.all([App.rpc('get_staff'), App.rpc('get_shift_types')]);
      S.staff = r[0]; S.types = r[1];
    },

    // その日の勤務。同じ日なら読み直さない
    async loadShifts(date) {
      if (S.date === date) return;
      try {
        S.shifts = await App.rpc('get_shifts', { p_from: date, p_to: date });
        S.date = date;
      } catch (err) {
        console.error(err);
        S.shifts = [];
        S.date = null;
      }
    },

    // 見出し: 今日なら「本日のスタッフ」、ほかの日は「10/16 のスタッフ」
    title: function (date) {
      return date === App.todayJST() ? '本日のスタッフ' : (+date.slice(5, 7)) + '/' + (+date.slice(8, 10)) + ' のスタッフ';
    },

    // box に帯を描く。戻り値は見出しの右に出す人数(「3人・いま 1人」。いなければ空)
    render: function (box, houseId, date) {
      const esc = App.escapeHtml;
      // この日(0:00〜24:00)にかかる勤務。前日からの夜勤も含める
      const items = S.shifts.filter(function (s) { return s.house_id === houseId; }).map(function (s) {
        const start = dayOffset(s.work_date, date) * DAY + minOf(s.start_time);
        return { s: s, start: start, end: start + durationOf(s) };
      }).filter(function (x) { return x.end > 0 && x.start < DAY; })
        .sort(function (a, b) { return a.start - b.start || a.end - b.end; });

      const isToday = date === App.todayJST();
      const nowParts = new Date(Date.now() + 9 * 3600 * 1000).toISOString().slice(11, 16).split(':');
      const nowMin = (+nowParts[0]) * 60 + (+nowParts[1]);

      let html = '<div class="tl-scale"><span></span><div class="tl-ticks">' +
        [0, 6, 12, 18, 24].map(function (h) { return '<span style="left:' + (h / 24 * 100) + '%">' + h + '時</span>'; }).join('') +
        '</div></div>';
      if (!items.length) html += '<div class="empty-msg">この日のスタッフはいません</div>';
      items.forEach(function (x) {
        const st = S.staff.find(function (p) { return p.id === x.s.staff_id; });
        const t = x.s.shift_type_id ? S.types.find(function (y) { return y.id === x.s.shift_type_id; }) : null;
        const a = Math.max(0, x.start), b = Math.min(DAY, x.end);
        const here = isToday && x.start <= nowMin && nowMin < x.end;
        const night = crosses(x.s) || (t && /夜/.test(t.name));
        const cls = 'tl-bar' + (night ? ' night' : '') + (x.start < 0 ? ' cont-left' : '') + (x.end > DAY ? ' cont-right' : '');
        const when = (x.start < 0 ? '前日 ' : '') + shiftText(x.s) + (t ? ' / ' + t.name : '') + (x.s.note ? ' / ' + x.s.note : '');
        html += '<div class="tl-row' + (here ? ' here' : '') + '">' +
          '<div class="tl-name">' + esc(st ? st.name : '?') + '<small>' + esc(st && st.job_title ? st.job_title : '') + '</small></div>' +
          '<div><div class="tl-track">' +
            (isToday ? '<div class="tl-now" style="left:' + (nowMin / DAY * 100) + '%"></div>' : '') +
            '<div class="' + cls + '" style="left:' + (a / DAY * 100) + '%;width:' + ((b - a) / DAY * 100) + '%">' + esc(x.start < 0 ? '〜' + hm(x.s.end_time) : hm(x.s.start_time)) + '</div>' +
          '</div><div class="tl-time">' + esc(when) + '</div></div>' +
          '</div>';
      });
      box.innerHTML = html;

      if (!items.length) return '';
      const people = new Set(items.map(function (x) { return x.s.staff_id; })).size;
      const hereNow = isToday ? new Set(items.filter(function (x) { return x.start <= nowMin && nowMin < x.end; }).map(function (x) { return x.s.staff_id; })).size : 0;
      return people + '人' + (isToday ? '・いま ' + hereNow + '人' : '');
    },
  };

  window.StaffDay = S;
})();
