// =====================================================
// バイタルの共通処理(family.html・vitals.html・records.html で使う)
//   読み込み順: common.js のあと
//   Vitals.openForm(...) でスタッフ用の入力ダイアログを開く(日々の記録・バイタルの画面から)
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

  // ===== スタッフ用の入力ダイアログ =====
  // opts: { residentId, name, date, time('HH:MM'。なければいま), ctxHtml(上のオレンジの帯。なければ名前と日付), onChange(その日のバイタルの配列) }
  const $ = function (id) { return document.getElementById(id); };
  const esc = function (s) { return App.escapeHtml(s); };
  let opts = null, dayRows = [], bathSel = null, built = false;

  function build() {
    if (built) return;
    built = true;
    const el = document.createElement('div');
    el.id = 'vtModal';
    el.className = 'modal-backdrop';
    el.hidden = true;
    el.innerHTML =
      '<div class="modal" role="dialog" aria-modal="true" aria-labelledby="vtfHead">' +
        '<div class="modal-head"><h2 id="vtfHead"><i class="ti ti-heartbeat"></i><span id="vtfTitle"></span></h2>' +
        '<button type="button" class="icon-btn" id="vtfClose" aria-label="閉じる"><i class="ti ti-x"></i></button></div>' +
        '<div class="modal-sticky"><div class="vtf-ctx" id="vtfCtx"></div></div>' +
        '<p class="vtf-note">はかったものだけ入れてください。はかっていないものは空のままでかまいません</p>' +
        '<div class="vt-grid">' +
          '<div class="field"><label for="vtfTime">はかった時間</label><input type="time" id="vtfTime"></div>' +
          '<div class="field"><label for="vtfTemp">体温(℃)</label><input type="number" id="vtfTemp" inputmode="decimal" step="0.1" min="34" max="42" placeholder="36.5"></div>' +
          '<div class="field"><label for="vtfHigh">血圧(上 / 下)</label><div class="bp-row">' +
            '<input type="number" id="vtfHigh" inputmode="numeric" min="50" max="260" placeholder="120" aria-label="血圧の上"><span>/</span>' +
            '<input type="number" id="vtfLow" inputmode="numeric" min="30" max="160" placeholder="80" aria-label="血圧の下"></div></div>' +
          '<div class="field"><label for="vtfPulse">脈拍(回/分)</label><input type="number" id="vtfPulse" inputmode="numeric" min="30" max="200" placeholder="70"></div>' +
        '</div>' +
        '<p class="vtf-label">前日、お風呂かシャワーに入りましたか?(どちらかを押す)</p>' +
        '<div class="vt-bath-row" id="vtfBath">' +
          '<button type="button" class="vt-bath-btn" data-bath="bath"><i class="ti ti-bath"></i>お風呂</button>' +
          '<button type="button" class="vt-bath-btn" data-bath="shower"><i class="ti ti-droplet"></i>シャワー</button>' +
        '</div>' +
        '<div class="vtf-hist-head" id="vtfHistHead" hidden>この日のバイタル</div>' +
        '<ul class="vtf-hist" id="vtfHist"></ul>' +
        '<div class="modal-foot">' +
          '<div id="vtfStatus" class="status-msg center"></div>' +
          '<button type="button" class="btn btn-block" id="vtfSave"><i class="ti ti-check"></i>記録する</button>' +
        '</div>' +
      '</div>';
    document.body.appendChild(el);
    el.addEventListener('click', function (e) { if (e.target === el) V.closeForm(); });
    $('vtfClose').addEventListener('click', V.closeForm);
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape') V.closeForm(); });
    $('vtfBath').addEventListener('click', function (e) {
      const b = e.target.closest('button[data-bath]');
      if (!b) return;
      bathSel = bathSel === b.dataset.bath ? null : b.dataset.bath;   // もう一度押すと外れる
      renderForm();
    });
    $('vtfSave').addEventListener('click', onSave);
    $('vtfHist').addEventListener('click', function (e) {
      const b = e.target.closest('button[data-void]');
      if (b) onVoid(b.dataset.void);
    });
  }

  function nowText() {
    const d = new Date(Date.now() + 9 * 3600 * 1000);
    return String(d.getUTCHours()).padStart(2, '0') + ':' + String(d.getUTCMinutes()).padStart(2, '0');
  }
  function num(id) { const v = $(id).value.trim(); return v === '' ? null : Number(v); }

  function resetForm(time) {
    $('vtfTime').value = time || nowText();
    ['vtfTemp', 'vtfHigh', 'vtfLow', 'vtfPulse'].forEach(function (id) { $(id).value = ''; });
    bathSel = null;
  }

  // 1 件の値を短く(履歴・日々の記録の一覧で使う)
  V.summary = function (v) {
    const vals = [];
    if (v.temperature !== null && v.temperature !== undefined) vals.push('体温 ' + V.temp(v.temperature));
    if (v.bp_high) vals.push('血圧 ' + V.bp(v));
    if (v.pulse) vals.push('脈拍 ' + V.pulse(v.pulse));
    if (v.bath_prev_day) vals.push('前日 ' + V.bath(v.bath_prev_day));
    return vals.join('  ');
  };

  function renderForm() {
    $('vtfBath').querySelectorAll('button').forEach(function (b) {
      b.classList.toggle('active', b.dataset.bath === bathSel);
      b.setAttribute('aria-pressed', b.dataset.bath === bathSel);
    });
    $('vtfHistHead').hidden = !dayRows.length;
    $('vtfHist').innerHTML = dayRows.slice().reverse().map(function (v) {
      return '<li><span class="t">' + esc(V.time(v.measured_time)) + '</span><span class="vals">' + esc(V.summary(v)) + '</span>' +
        '<button type="button" class="btn btn-ghost btn-sm" data-void="' + esc(v.id) + '">取消</button></li>';
    }).join('');
  }

  V.openForm = async function (o) {
    build();
    opts = o;
    dayRows = [];
    $('vtfTitle').textContent = o.name + ' さんのバイタル';
    $('vtfCtx').innerHTML = o.ctxHtml || ('<div class="vtf-line"><i class="ti ti-heartbeat"></i>' + esc(o.name) + ' さんのバイタルを入力中です</div>' +
      '<div class="vtf-line"><i class="ti ti-calendar"></i>' + esc(window.Rooms ? window.Rooms.dateText(o.date) : o.date) + '</div>');
    resetForm(o.time);
    App.setStatus($('vtfStatus'), '');
    renderForm();
    $('vtModal').hidden = false;
    try {
      dayRows = await App.rpc('get_vitals', { p_from: o.date, p_to: o.date, p_resident_id: o.residentId });
    } catch (err) {
      console.error(err);
      App.setStatus($('vtfStatus'), 'この日のバイタルを読み込めませんでした', 'err');
    }
    if (opts === o) renderForm();
  };
  V.closeForm = function () {
    if (!built) return;
    $('vtModal').hidden = true;
    opts = null;
  };

  async function onSave() {
    if (!opts) return;
    const o = opts;
    const st = $('vtfStatus');
    const temp = num('vtfTemp'), hi = num('vtfHigh'), lo = num('vtfLow'), pulse = num('vtfPulse');
    if (!$('vtfTime').value) return App.setStatus(st, 'はかった時間を入れてください', 'err');
    if (temp === null && hi === null && lo === null && pulse === null && !bathSel) return App.setStatus(st, 'はかった値を入れてください', 'err');
    if ((hi === null) !== (lo === null)) return App.setStatus(st, '血圧は上と下の両方を入れてください', 'err');
    const btn = $('vtfSave');
    btn.disabled = true;
    let row;
    try {
      row = await App.rpc('add_vital', {
        p_resident_id: o.residentId, p_date: o.date, p_time: $('vtfTime').value,
        p_temperature: temp, p_bp_high: hi === null ? null : Math.round(hi), p_bp_low: lo === null ? null : Math.round(lo),
        p_pulse: pulse === null ? null : Math.round(pulse), p_bath: bathSel, p_by: 'staff',
      });
    } catch (err) {
      console.error(err);
      // 値の範囲など、DB からの説明はそのまま見せる
      const m = err && err.message ? err.message : '';
      App.setStatus(st, /入れてください|確かめて/.test(m) ? m : '記録できませんでした。通信状況を確認してください', 'err');
      btn.disabled = false;
      return;
    }
    btn.disabled = false;
    dayRows = dayRows.concat([row]).sort(function (a, b) { return a.measured_time < b.measured_time ? -1 : a.measured_time > b.measured_time ? 1 : 0; });
    V.closeForm();
    if (o.onChange) o.onChange(dayRows, V.time(row.measured_time) + ' のバイタルを記録しました');
  }

  async function onVoid(id) {
    if (!opts) return;
    const o = opts;
    const v = dayRows.find(function (x) { return x.id === id; });
    if (!v || !confirm(V.time(v.measured_time) + ' のバイタルを取り消しますか?')) return;
    try {
      await App.rpc('void_vital', { p_id: id });
    } catch (err) {
      console.error(err);
      App.setStatus($('vtfStatus'), '取り消せませんでした', 'err');
      return;
    }
    dayRows = dayRows.filter(function (x) { return x.id !== id; });
    App.setStatus($('vtfStatus'), '取り消しました', 'ok');
    renderForm();
    if (o.onChange) o.onChange(dayRows, '');
  }

  window.Vitals = V;
})();
