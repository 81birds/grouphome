// =====================================================
// 共通処理(全画面で読み込む)
//   読み込み順: supabase-js → config.js → common.js → ページのスクリプト
//   ページ側は App.boot({ active: 'residents', onReady }) を呼ぶだけでよい。
//
// リンクは「residents.html」のような相対パスで書く。
//   ・VS Code の Live Server でもそのまま開ける
//   ・Vercel では cleanUrls により /residents に自動で移動する
// =====================================================
(function () {
  'use strict';

  const cfg = window.APP_CONFIG;
  const sb = window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY);

  // 流通ポータルと同じく、合言葉はブラウザの localStorage に保存する
  const PASSCODE_KEY = 'gh_passcode';

  // ----- 画面一覧 -----
  // ここに足すと、上部タブとポータルのタイルの両方に出る。
  // ready: false の画面はポータルに「準備中」で表示され、タブには出ない。
  const PAGES = [
    { key: 'index',      file: 'index.html',      icon: 'ti-home-heart', label: 'ポータル',   sub: '',                       ready: true, portal: false },
    { key: 'family',     file: 'family.html',     icon: 'ti-device-mobile-message', label: '利用者さん画面', sub: 'スマホ操作が可能な利用者さん用', ready: true },
    { key: 'records',    file: 'records.html',    icon: 'ti-notebook',   label: '日々の記録', sub: '食事・外出・お薬の記録', ready: true },
    { key: 'shifts',     file: 'shifts.html',     icon: 'ti-calendar-time', label: '勤務表',  sub: '1か月のシフト・個人の勤務', ready: true },
    { key: 'meals',      file: 'meals.html',      icon: 'ti-tools-kitchen-2', label: '食数管理', sub: 'ハウスごとの食べる・食べない', ready: true },
    { key: 'vitals',     file: 'vitals.html',     icon: 'ti-heartbeat',  label: 'バイタル',   sub: '体温・血圧・脈拍・入浴', ready: true },
    { key: 'medication', file: 'medication.html', icon: 'ti-pill',       label: '服薬',       sub: '朝・昼・夕・寝る前のお薬と空包確認', ready: true },
    { key: 'handover',   file: 'handover.html',   icon: 'ti-messages',   label: '申し送り',   sub: 'スタッフ間の連絡',       ready: false },
    { key: 'residents',  file: 'residents.html',  icon: 'ti-users',      label: '利用者さんDB',   sub: '利用者さん一覧・基本情報',   ready: true },
    { key: 'staff',      file: 'staff.html',      icon: 'ti-id-badge-2', label: 'スタッフDB', sub: 'スタッフ一覧・所属施設', ready: true },
    { key: 'houses',     file: 'houses.html',     icon: 'ti-building-community', label: '施設DB', sub: '施設一覧・住所・定員', ready: true },
    { key: 'settings',   file: 'settings.html',   icon: 'ti-settings',   label: '設定',       sub: '合言葉などの設定',       ready: false },
    { key: 'supplies',   file: 'supplies.html',   icon: 'ti-package',    label: '備品管理',   sub: '施設の発注・本部の手配', ready: true },
    { key: 'dev',        file: 'dev.html',        icon: 'ti-code',       label: '開発者',     sub: 'アプリの概要・ダミーデータにもどす', ready: true },
  ];

  // ----- 上部のタブ -----
  function renderNav(activeKey) {
    const nav = document.getElementById('gtoolBar');
    if (!nav) return;
    nav.className = 'gtool-bar';
    nav.setAttribute('aria-label', '画面の切り替え');
    nav.innerHTML = PAGES.filter(function (p) { return p.ready; }).map(function (p) {
      const active = p.key === activeKey ? ' active' : '';
      return '<a href="' + p.file + '" class="gtool-tab' + active + '">' +
        '<i class="ti ' + p.icon + '"></i><span>' + escapeHtml(p.label) + '</span></a>';
    }).join('');
  }

  // ----- 合言葉 -----
  function getPasscode() {
    try { return localStorage.getItem(PASSCODE_KEY) || ''; } catch (e) { return ''; }
  }
  function savePasscode(code) {
    try { localStorage.setItem(PASSCODE_KEY, code); } catch (e) { /* 保存できなくても続ける */ }
  }
  function clearPasscode() {
    try { localStorage.removeItem(PASSCODE_KEY); } catch (e) { /* noop */ }
  }

  // 合言葉が正しければ true、違えば false。通信エラーは例外にする
  async function checkPasscode(code) {
    const res = await sb.rpc('check_passcode', { input_passcode: code });
    if (!res.error) return true;
    if (/合言葉が違います/.test(res.error.message)) return false;
    throw res.error;
  }

  function goLogin() {
    const here = location.pathname.split('/').pop() || 'index.html';
    location.replace('login.html?next=' + encodeURIComponent(here + location.search));
  }

  function logout() {
    clearPasscode();
    location.replace('login.html');
  }

  // ----- DB の関数を呼ぶ(合言葉を自動で付ける) -----
  //   const rows = await App.rpc('get_residents');
  //   await App.rpc('add_resident', { p_name: '...' });
  async function rpc(fnName, params) {
    const args = Object.assign({ input_passcode: getPasscode() }, params || {});
    const res = await sb.rpc(fnName, args);
    if (res.error) {
      // 途中で合言葉が変わったときはログイン画面へ
      if (/合言葉が違います/.test(res.error.message)) {
        clearPasscode();
        goLogin();
      }
      throw res.error;
    }
    return res.data;
  }

  function showMain() {
    const loading = document.getElementById('loadingScreen');
    const main = document.getElementById('mainContent');
    if (loading) loading.hidden = true;
    if (main) main.hidden = false;
  }

  function showFatal(message) {
    const loading = document.getElementById('loadingScreen');
    if (!loading) return alert(message);
    loading.hidden = false;
    loading.innerHTML =
      '<i class="ti ti-alert-triangle" style="color:var(--color-danger)"></i>' +
      '<div>' + escapeHtml(message) + '</div>' +
      '<button class="btn" onclick="location.reload()">再読み込みする</button>';
  }

  // ----- ページの起動 -----
  async function boot(opts) {
    renderNav(opts.active);
    const code = getPasscode();
    if (!code) return goLogin();
    try {
      const ok = await checkPasscode(code);
      if (!ok) { clearPasscode(); return goLogin(); }
      if (opts.onReady) await opts.onReady();
      showMain();
    } catch (e) {
      console.error(e);
      showFatal('読み込みに失敗しました。通信状況を確認してください。');
    }
  }

  // ----- 小さな道具 -----
  function escapeHtml(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  // 「中村 健一 さん」の HTML。狭い欄でも、改行は姓と名の間だけにして、「さん」は名前から離さない
  function nameSan(name) {
    const parts = String(name == null ? '' : name).trim().split(/[\s　]+/);
    const last = parts.pop();
    return parts.map(function (p) { return '<span class="nw">' + escapeHtml(p) + '</span> '; }).join('') +
      '<span class="nw">' + escapeHtml(last) + '&nbsp;さん</span>';
  }

  // 日本時間の今日を YYYY-MM-DD で返す(offsetDays で前後の日)
  function todayJST(offsetDays) {
    const d = new Date(Date.now() + 9 * 3600 * 1000 + (offsetDays || 0) * 86400 * 1000);
    return d.toISOString().slice(0, 10);
  }

  // 入力欄に保存結果を一瞬表示する(要 class="autosave")
  function flashSaved(el, ok) {
    el.classList.remove('saved', 'save-error');
    void el.offsetWidth;
    el.classList.add(ok ? 'saved' : 'save-error');
    if (ok) setTimeout(function () { el.classList.remove('saved'); }, 50);
  }

  function setStatus(el, message, kind) {
    el.textContent = message || '';
    el.className = 'status-msg' + (kind ? ' ' + kind : '');
  }

  window.App = {
    sb: sb,
    config: cfg,
    PAGES: PAGES,
    boot: boot,
    rpc: rpc,
    renderNav: renderNav,
    getPasscode: getPasscode,
    savePasscode: savePasscode,
    checkPasscode: checkPasscode,
    logout: logout,
    escapeHtml: escapeHtml,
    nameSan: nameSan,
    todayJST: todayJST,
    flashSaved: flashSaved,
    setStatus: setStatus,
  };
})();
