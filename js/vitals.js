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


  // ===== ダイヤル(ホイール)で入れる部品 =====
  // Vitals.dials(container) で体温・血圧・脈拍のダイヤルを作る。family.html とスタッフ用ダイアログで使う
  //   はじめは「入れない」(うすい色)。回すか値を押すと「入れる」になり、× でもどす(はかったものだけ入れるため)
  //   返り値: { get() → { temperature, bp_high, bp_low, pulse }(入れないものは null), reset() }
  //   reset() は隠れているときに呼んでも、画面に出たときに位置を合わせる
  const DIALS = [
    { key: 'temp',  label: '体温', unit: '℃', sep: '.',
      cols: [{ min: 34, max: 42, init: 36 }, { min: 0, max: 9, init: 5 }] },
    { key: 'bp',    label: '血圧(上 / 下)', unit: '', sep: '/',
      cols: [{ min: 60, max: 220, init: 120 }, { min: 30, max: 140, init: 80 }] },
    { key: 'pulse', label: '脈拍', unit: '回/分',
      cols: [{ min: 30, max: 180, init: 70 }] },
  ];
  V.dials = function (box) {
    box.classList.add('vd-grid');
    box.innerHTML = DIALS.map(function (d) {
      const cols = d.cols.map(function (c, i) {
        let items = '';
        for (let v = c.min; v <= c.max; v++) items += '<div class="vd-item" data-i="' + (v - c.min) + '">' + v + '</div>';
        return (i ? '<div class="vd-sep">' + d.sep + '</div>' : '') + '<div class="vd-col" data-c="' + i + '">' + items + '</div>';
      }).join('');
      return '<div class="vd-block off" data-key="' + d.key + '">' +
        '<div class="vd-head"><span class="vd-label">' + d.label + '</span><span class="vd-val"></span>' +
        '<button type="button" class="vd-clear" aria-label="' + d.label + 'を入れない" title="入れない"><i class="ti ti-x"></i></button></div>' +
        '<div class="vd-wheel"><div class="vd-band"></div>' + cols + (d.unit ? '<span class="vd-unit">' + d.unit + '</span>' : '') + '</div>' +
        '</div>';
    }).join('');

    function blockOf(key) { return box.querySelector('.vd-block[data-key="' + key + '"]'); }
    function itemH(col) { return (col.firstElementChild && col.firstElementChild.offsetHeight) || 34; }
    function idx(col) {
      const n = col.children.length;
      return Math.max(0, Math.min(n - 1, Math.round(col.scrollTop / itemH(col))));
    }
    // 1 つのダイヤルの値(列ごとの数)
    function nums(block) {
      const d = DIALS.find(function (x) { return x.key === block.dataset.key; });
      return Array.prototype.map.call(block.querySelectorAll('.vd-col'), function (col, i) { return d.cols[i].min + idx(col); });
    }
    function valueOf(block) {
      const n = nums(block);
      if (block.dataset.key === 'temp') return { temperature: Math.min(42, Math.round((n[0] + n[1] / 10) * 10) / 10) };
      if (block.dataset.key === 'bp') return { bp_high: n[0], bp_low: n[1] };
      return { pulse: n[0] };
    }
    // 見出しの値(目安を外れたら赤)と、選んでいる段の印
    function paint(block) {
      block.querySelectorAll('.vd-col').forEach(function (col) {
        const v = idx(col);
        Array.prototype.forEach.call(col.children, function (el, i) { el.classList.toggle('sel', i === v); });
      });
      const out = block.querySelector('.vd-val');
      if (block.classList.contains('off')) { out.className = 'vd-val'; out.textContent = '回すと入ります'; return; }
      const v = valueOf(block);
      let text, alert;
      if (v.temperature !== undefined) { text = V.temp(v.temperature); alert = V.alert('temperature', v.temperature); }
      else if (v.bp_high !== undefined) { text = v.bp_high + '/' + v.bp_low; alert = V.alert('bp_high', v.bp_high) || V.alert('bp_low', v.bp_low); }
      else { text = V.pulse(v.pulse); alert = V.alert('pulse', v.pulse); }
      out.className = 'vd-val on' + (alert ? ' alert' : '');
      out.textContent = text;
    }
    function setOn(block, on) {
      block.classList.toggle('off', !on);
      paint(block);
    }

    box.querySelectorAll('.vd-block').forEach(function (block) {
      const wheel = block.querySelector('.vd-wheel');
      // 人がさわったら「入れる」に(プログラムでのスクロールでは変えない)
      ['pointerdown', 'wheel', 'touchstart'].forEach(function (ev) {
        wheel.addEventListener(ev, function () { if (block.classList.contains('off')) setOn(block, true); }, { passive: true });
      });
      block.querySelectorAll('.vd-col').forEach(function (col) {
        let raf = 0;
        col.addEventListener('scroll', function () {
          cancelAnimationFrame(raf);
          raf = requestAnimationFrame(function () { paint(block); });
        }, { passive: true });
        col.addEventListener('click', function (e) {
          const it = e.target.closest('.vd-item');
          if (it) col.scrollTo({ top: +it.dataset.i * itemH(col), behavior: 'smooth' });
        });
      });
      block.querySelector('.vd-clear').addEventListener('click', function () { setOn(block, false); });
    });

    let pending = false;
    if (window.ResizeObserver) {
      new ResizeObserver(function () { if (pending && box.offsetHeight) api.reset(); }).observe(box);
    }
    const api = {
      get: function () {
        const out = { temperature: null, bp_high: null, bp_low: null, pulse: null };
        box.querySelectorAll('.vd-block').forEach(function (block) {
          if (!block.classList.contains('off')) Object.assign(out, valueOf(block));
        });
        return out;
      },
      // ぜんぶ「入れない」にして、よくある値の位置にもどす
      // まだ画面に出ていない(読み込み中など)ときは、出たときに合わせる
      reset: function () {
        if (!box.offsetHeight) { pending = true; return; }
        pending = false;
        DIALS.forEach(function (d) {
          const block = blockOf(d.key);
          block.classList.add('off');
          block.querySelectorAll('.vd-col').forEach(function (col, i) { col.scrollTop = (d.cols[i].init - d.cols[i].min) * itemH(col); });
          paint(block);
        });
      },
    };
    return api;
  };

  // ===== スタッフ用の入力ダイアログ =====
  // opts: { residentId, name, date, time('HH:MM'。なければいま), ctxHtml(上のオレンジの帯。なければ名前と日付), onChange(その日のバイタルの配列) }
  const $ = function (id) { return document.getElementById(id); };
  const esc = function (s) { return App.escapeHtml(s); };
  let opts = null, dayRows = [], bathSel = null, built = false, dials = null;

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
        '<p class="vtf-note">はかったものだけ、ダイヤルを回して入れてください。回さないものは入りません</p>' +
        '<div class="field vtf-time"><label for="vtfTime">はかった時間</label><input type="time" id="vtfTime"></div>' +
        '<div id="vtfDials"></div>' +
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
    dials = V.dials($('vtfDials'));
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
  function resetForm(time) {
    $('vtfTime').value = time || nowText();
    dials.reset();
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
    $('vtModal').hidden = false;      // ダイヤルの位置は、出してから決める
    resetForm(o.time);
    App.setStatus($('vtfStatus'), '');
    renderForm();
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
    const d = dials.get();
    const temp = d.temperature, hi = d.bp_high, lo = d.bp_low, pulse = d.pulse;
    if (!$('vtfTime').value) return App.setStatus(st, 'はかった時間を入れてください', 'err');
    if (temp === null && hi === null && lo === null && pulse === null && !bathSel) return App.setStatus(st, 'はかったもののダイヤルを回してください', 'err');
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
