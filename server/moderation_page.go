package main

// moderationPageHTML is a single self-contained admin page: no build step, no
// external assets. The admin token stays in the page URL and is appended to
// every fetch call by JS (POSTs also send X-Admin-Token, which /admin/grant_shards
// requires); the server injects nothing into this file.
const moderationPageHTML = `<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<title>Админка — Небесные осколки</title>
<style>
:root{--bg:#0b1018;--panel:#131c28;--line:#243349;--text:#e8eef7;--muted:#93a2b8;--gold:#f2c76e;--ok:#63d68b;--warn:#f0b45c;--bad:#ff7070;--blue:#7cc0ff}
*{box-sizing:border-box}
body{margin:0;background:radial-gradient(1100px 460px at 50% -10%,#1a2c46 0%,var(--bg) 60%);color:var(--text);font:14px/1.45 'Segoe UI',system-ui,Arial,sans-serif}
.wrap{max-width:1500px;margin:0 auto;padding:22px 18px 56px}
header{display:flex;flex-wrap:wrap;gap:12px;align-items:flex-end;justify-content:space-between;margin-bottom:16px}
h1{margin:0;font:600 26px/1.2 Georgia,serif;color:var(--gold);letter-spacing:.4px}
.sub{margin:4px 0 0;color:var(--muted);font-size:13px}
h2{margin:0;font-size:15px;color:var(--gold);letter-spacing:.3px}
.panel{background:linear-gradient(180deg,var(--panel),#0e1621);border:1px solid var(--line);border-radius:14px;padding:14px 16px;margin-bottom:16px}
.panel-head{display:flex;flex-wrap:wrap;gap:10px;align-items:center;justify-content:space-between;margin-bottom:10px}
.table-wrap{overflow:auto;border:1px solid #1d293b;border-radius:10px}
table{border-collapse:collapse;width:100%;min-width:1100px}
th,td{padding:8px 10px;text-align:left;vertical-align:top;border-bottom:1px solid #1d293b}
th{position:sticky;top:0;background:#172231;color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.5px;font-weight:600;z-index:1}
tr:last-child td{border-bottom:0}
tbody tr:hover{background:#16202e}
.muted{color:var(--muted)}
.small{font-size:12px}
.reason{min-width:180px;max-width:320px;white-space:pre-wrap;word-break:break-word}
button{font:inherit;color:var(--text);background:#1d2a3c;border:1px solid #2d3f58;border-radius:8px;padding:5px 10px;cursor:pointer}
button:hover{background:#26374e}
button:disabled{opacity:.45;cursor:default}
button.primary{background:#274469;border-color:#3a6090}
button.mini{padding:3px 8px;font-size:12px;margin:1px}
button.ok{border-color:#2f6b4a;color:#bdf3d2}
button.warn{border-color:#7a5a24;color:#ffe1ab}
button.bad{border-color:#7d3232;color:#ffc2c2}
input,select{font:inherit;color:var(--text);background:#0f1824;border:1px solid #2d3f58;border-radius:8px;padding:5px 9px}
.controls{display:flex;flex-wrap:wrap;gap:8px;align-items:center}
.check{display:inline-flex;gap:6px;align-items:center;cursor:pointer}
.check input{margin:0}
.badge{display:inline-block;margin-left:6px;padding:1px 7px;border-radius:999px;border:1px solid #3b4d68;color:var(--muted);font-size:11px;vertical-align:middle}
.badge.bad{border-color:#7d3232;color:#ffb4b4}
.badge.warn{border-color:#7a5a24;color:#ffd99b}
.badge.ok{border-color:#2f6b4a;color:#bdf3d2}
.grant{display:flex;gap:6px;align-items:center;margin-top:6px}
.grant input{width:86px;padding:3px 7px;font-size:12px}
.pager{display:flex;flex-wrap:wrap;gap:10px;align-items:center;justify-content:space-between;margin-top:10px}
.pager-buttons{display:flex;gap:6px}
.modal{position:fixed;inset:0;z-index:50;display:flex;align-items:flex-start;justify-content:center;padding:24px 14px;background:rgba(3,7,12,.74);overflow:auto}
.modal[hidden]{display:none}
.modal-card{width:min(760px,100%);background:linear-gradient(180deg,var(--panel),#0e1621);border:1px solid var(--line);border-radius:16px;padding:16px 18px 18px;box-shadow:0 20px 60px rgba(0,0,0,.55)}
.modal-head{display:flex;gap:12px;align-items:center;justify-content:space-between;margin-bottom:8px}
.modal-head h2{font-size:18px;margin:0}
body.modal-open{overflow:hidden}
.m-section{border-top:1px solid #1d293b;padding-top:12px;margin-top:12px}
.m-section:first-child{border-top:0;padding-top:0;margin-top:0}
.m-section h3{margin:0 0 8px;font-size:13px;color:var(--gold);text-transform:uppercase;letter-spacing:.5px}
.m-row{display:flex;flex-wrap:wrap;gap:8px;align-items:center}
.m-row input[type=number]{width:120px}
.xp-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px;margin-bottom:10px}
.xp-card{border:1px solid #243349;border-radius:10px;padding:8px 10px;background:#101a27}
.xp-card b{display:block;color:var(--gold)}
.chips{display:flex;flex-wrap:wrap;gap:6px;margin-bottom:10px}
.chip{display:inline-flex;gap:6px;align-items:center;padding:3px 4px 3px 9px;border:1px solid #2d3f58;border-radius:999px;background:#101a27;font-size:12px}
.chip button{border:1px solid #7d3232;border-radius:999px;background:#241417;color:#ffb4b4;padding:1px 7px;font-size:11px}
.chip button:hover{background:#331b1e;color:#ffd0d0}
.m-status{margin:6px 0 0;padding:8px 10px;border-radius:8px;border:1px solid #2f6b4a;background:#14251c;color:#bdf3d2;font-size:13px}
.m-status.bad{border-color:#7d3232;background:#2a1616;color:#ffc2c2}
.m-hint{font-size:12px;color:var(--muted);margin:8px 0 0}
@media (max-width:560px){.xp-grid{grid-template-columns:1fr}}
.notice{margin:0 0 14px;padding:10px 12px;border-radius:10px;border:1px solid #2f6b4a;background:#14251c;color:#bdf3d2}
.notice.bad{border-color:#7d3232;background:#2a1616;color:#ffc2c2}
.empty{padding:18px;text-align:center;color:var(--muted)}
.foot{margin-top:8px;font-size:12px}
.brand{color:var(--gold);font-weight:600}
</style>
</head>
<body>
<div class="wrap">
  <header>
    <div>
      <h1>Админка <span class="brand">Небесные осколки</span></h1>
      <p class="sub">Жалобы, игроки, осколки, опыт и инвентарь. Личная страница владельца; ссылка нигде в игре не публикуется.</p>
    </div>
    <div>
      <button class="primary" id="reload" type="button">Обновить</button>
      <span class="muted small" id="status"></span>
    </div>
  </header>

  <div class="notice" id="notice" hidden></div>

  <section class="panel">
    <div class="panel-head">
      <h2>Жалобы</h2>
      <label class="muted small">Показать:
        <select id="filter">
          <option value="open">открытые</option>
          <option value="resolved">решённые</option>
          <option value="all">все</option>
        </select>
      </label>
    </div>
    <div class="table-wrap">
      <table>
        <thead><tr>
          <th>#</th><th>Когда</th><th>Прошло</th><th>На кого</th><th>Пожаловался</th>
          <th>Причина</th><th>Матч</th><th>Статус</th><th>Действия</th>
        </tr></thead>
        <tbody id="reports"><tr><td class="empty" colspan="9">Загрузка…</td></tr></tbody>
      </table>
    </div>
    <p class="foot muted">«Скрыть ник», «Предупредить» и «Бан» записывают флаги игрока. Предупреждения считаются, у последнего хранятся причина и время. Если ник встречается у нескольких игроков, страница попросит player_id.</p>
  </section>

  <section class="panel">
    <div class="panel-head">
      <h2>Игроки</h2>
      <form id="search-form" class="controls">
        <label class="muted small check"><input id="all" type="checkbox" checked> Все игроки</label>
        <input id="q" type="search" placeholder="часть ника" autocomplete="off" maxlength="64">
        <button type="submit">Найти</button>
        <button type="button" id="clear-search">Сбросить</button>
      </form>
    </div>
    <div class="table-wrap">
      <table>
        <thead><tr>
          <th>ID</th><th>Ник</th><th>Платформа</th><th>Матчи</th><th>Осколки</th>
          <th title="Уровень аккаунта; уровни персонажей — в «Прогресс/инвентарь»">Уровень</th><th>Последний вход</th><th>Жалобы</th><th>Действия</th>
        </tr></thead>
        <tbody id="players"><tr><td class="empty" colspan="9">Загрузка…</td></tr></tbody>
      </table>
    </div>
    <div class="pager">
      <span class="muted small" id="players-count">Показано 0–0 из 0</span>
      <span class="pager-buttons">
        <button type="button" id="players-prev" disabled>← Назад</button>
        <button type="button" id="players-next" disabled>Вперёд →</button>
      </span>
    </div>
    <p class="foot muted">По умолчанию показаны все игроки. Снимите «Все игроки», чтобы увидеть только забаненных, скрытых, недавно заходивших и тех, на кого жаловались. «Прогресс/инвентарь» открывает осколки, опыт и купленные предметы.</p>
  </section>
</div>

<div class="modal" id="player-modal" hidden>
  <div class="modal-card" role="dialog" aria-modal="true" aria-labelledby="modal-title">
    <div class="modal-head">
      <h2 id="modal-title">Игрок</h2>
      <button type="button" id="modal-close" aria-label="Закрыть">×</button>
    </div>
    <div class="m-status" id="modal-status" hidden></div>
    <div id="modal-body"></div>
  </div>
</div>
<script>
(function () {
  'use strict';
  var token = new URLSearchParams(location.search).get('token') || '';
  var reports = [];
  var players = [];
  var lastQuery = '';
  var pageSize = 100;
  var offset = 0;
  var totalPlayers = 0;
  var playersRequest = 0;
  var modalPlayer = null;
  var actionBusy = false;

  var noticeBox = document.getElementById('notice');
  var statusBox = document.getElementById('status');
  var reportsBody = document.getElementById('reports');
  var playersBody = document.getElementById('players');
  var filterBox = document.getElementById('filter');
  var allBox = document.getElementById('all');
  var playersCount = document.getElementById('players-count');
  var prevButton = document.getElementById('players-prev');
  var nextButton = document.getElementById('players-next');
  var modal = document.getElementById('player-modal');
  var modalBody = document.getElementById('modal-body');
  var modalTitle = document.getElementById('modal-title');
  var modalStatus = document.getElementById('modal-status');

  var characterNames = {warrior: 'Воин', mage: 'Маг', fairy: 'Фея'};
  var characterOrder = ['warrior', 'mage', 'fairy'];
  var weaponNames = {
    1: 'Двуручное оружие',
    2: 'Тяжёлый арбалет',
    3: 'Посох волшебника',
    4: 'Боевой топор',
    5: 'Короткий лук',
    6: 'Посох ученика',
    7: 'Стальной меч',
    8: 'Эльфийский лук',
    9: 'Кристальный посох',
    101: 'Скин «Варвар»',
    102: 'Скин «Охотница в капюшоне»'
  };

  function esc(value) {
    return String(value === null || value === undefined ? '' : value).replace(/[&<>"']/g, function (ch) {
      return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch];
    });
  }
  function fmtNumber(value) {
    var number = Number(value);
    if (!isFinite(number)) return '0';
    return number.toLocaleString('ru-RU');
  }
  function parseIDs(value) {
    var seen = {};
    return String(value || '').split(',').map(function (part) {
      return parseInt(part, 10);
    }).filter(function (id) {
      if (!isFinite(id) || id <= 0 || seen[id]) return false;
      seen[id] = true;
      return true;
    });
  }
  function totalXP(level, xp) {
    level = Math.max(1, Math.min(15, parseInt(level, 10) || 1));
    if (level >= 15) return 105000;
    xp = Math.max(0, Math.min(level * 1000 - 1, parseInt(xp, 10) || 0));
    return (level - 1) * level / 2 * 1000 + xp;
  }
  function fmtDate(value) {
    if (!value) return '—';
    var date = new Date(value);
    if (isNaN(date.getTime())) return '—';
    return date.toLocaleString('ru-RU');
  }
  function fmtAge(hours) {
    if (hours === null || hours === undefined || isNaN(hours)) return '—';
    if (hours < 1) return Math.max(1, Math.round(hours * 60)) + ' мин';
    if (hours < 48) return Math.round(hours) + ' ч';
    return Math.round(hours / 24) + ' дн';
  }
  function actionLabel(action) {
    var labels = {
      dismiss: 'жалоба отклонена',
      hide_nickname: 'ник скрыт',
      unhide_nickname: 'ник снова виден',
      warn: 'предупреждение',
      ban: 'бан',
      unban: 'бан снят',
      grant_xp: 'опыт изменён',
      remove_weapon: 'предмет забран',
      clear_weapons: 'оружие и скины забраны'
    };
    return labels[action] || action;
  }
  function grantErrorMessage(err) {
    var message = err && err.message ? err.message : 'Ошибка';
    var known = {
      'Invalid amount': 'сумма должна быть от 1 до 1 000 000',
      'Invalid JSON': 'сервер не принял запрос',
      'Player not found': 'игрок не найден',
      'Unknown character': 'неизвестный персонаж',
      'Invalid item id': 'некорректный id предмета',
      'Forbidden': 'нет доступа, проверьте ?token=… в адресе',
      'Database unavailable': 'база данных недоступна',
      'Internal server error': 'ошибка сервера, попробуйте ещё раз'
    };
    return known[message] || message;
  }
  function notice(text, bad) {
    noticeBox.textContent = text;
    noticeBox.hidden = false;
    noticeBox.className = bad ? 'notice bad' : 'notice';
    if (!bad) {
      setTimeout(function () { noticeBox.hidden = true; }, 6000);
    }
  }
  function setStatus(text) { statusBox.textContent = text; }

  function apiUrl(path) {
    var url = new URL(path, location.origin);
    if (token) url.searchParams.set('token', token);
    return url.toString();
  }
  async function getJSON(path) {
    var response = await fetch(apiUrl(path), {credentials: 'same-origin', cache: 'no-store'});
    var data;
    try { data = await response.json(); } catch (err) { throw new Error('HTTP ' + response.status); }
    if (!response.ok || data.success === false) throw new Error(data.error || ('HTTP ' + response.status));
    return data;
  }
  async function postJSON(path, body) {
    var headers = {'Content-Type': 'application/json'};
    if (token) headers['X-Admin-Token'] = token;
    var response = await fetch(apiUrl(path), {
      method: 'POST',
      credentials: 'same-origin',
      headers: headers,
      body: JSON.stringify(body)
    });
    var data;
    try { data = await response.json(); } catch (err) { throw new Error('HTTP ' + response.status); }
    if (!response.ok || data.success === false) throw new Error(data.error || ('HTTP ' + response.status));
    return data;
  }

  function statusCell(report) {
    if (report.status === 'open') return '<span class="badge warn">открыта</span>';
    var label = report.action ? actionLabel(report.action) : 'решена';
    return '<span class="small">' + esc(label) + '</span><div class="muted small">' + fmtDate(report.resolved_at) + '</div>';
  }
  function reportButtons(report) {
    if (report.status !== 'open') return '<span class="muted small">—</span>';
    function button(action, label, cls) {
      return '<button class="mini ' + cls + '" type="button" data-report-act="' + action + '" data-report="' + report.id + '">' + label + '</button>';
    }
    return button('dismiss', 'Отклонить', '') +
      button('hide_nickname', 'Скрыть ник', 'ok') +
      button('warn', 'Предупредить', 'warn') +
      button('ban', 'Бан', 'bad');
  }
  function renderReports() {
    if (!reports.length) {
      reportsBody.innerHTML = '<tr><td class="empty" colspan="9">Жалоб нет</td></tr>';
      return;
    }
    var html = [];
    reports.forEach(function (report) {
      var target = '<b>' + esc(report.reported_nickname) + '</b>';
      if (report.player_id) {
        target += '<div class="muted small">#' + report.player_id + (report.platform ? ' · ' + esc(report.platform) : '') + '</div>';
      }
      if (report.nickname_matches > 1 && !report.reported_player_id) {
        target += '<span class="badge warn">таких ников: ' + report.nickname_matches + '</span>';
      }
      if (report.banned) target += '<span class="badge bad">бан</span>';
      if (report.nickname_hidden) target += '<span class="badge">ник скрыт</span>';

      var reporter = report.reporter_nickname
        ? esc(report.reporter_nickname) + ' <span class="muted small">#' + report.reporter_id + '</span>'
        : '<span class="muted">#' + report.reporter_id + '</span>';

      html.push('<tr>' +
        '<td>' + report.id + '</td>' +
        '<td class="small">' + fmtDate(report.created_at) + '</td>' +
        '<td class="small">' + fmtAge(report.hours_open) + '</td>' +
        '<td>' + target + '</td>' +
        '<td class="small">' + reporter + '</td>' +
        '<td class="reason small">' + esc(report.reason) + '</td>' +
        '<td class="small">' + (report.room_id ? '#' + report.room_id : '—') + '</td>' +
        '<td>' + statusCell(report) + '</td>' +
        '<td>' + reportButtons(report) + '</td>' +
        '</tr>');
    });
    reportsBody.innerHTML = html.join('');
  }

  function playerButtons(player) {
    var html = '';
    if (player.banned) {
      html += '<button class="mini ok" type="button" data-player-act="unban" data-player="' + player.id + '">Разбан</button>';
    } else {
      html += '<button class="mini bad" type="button" data-player-act="ban" data-player="' + player.id + '">Бан</button>';
    }
    html += ' <button class="mini warn" type="button" data-player-act="warn" data-player="' + player.id + '">Предупредить</button>';
    if (player.nickname_hidden) {
      html += ' <button class="mini" type="button" data-player-act="unhide_nickname" data-player="' + player.id + '">Показать ник</button>';
    } else {
      html += ' <button class="mini" type="button" data-player-act="hide_nickname" data-player="' + player.id + '">Скрыть ник</button>';
    }
    html += ' <button class="mini primary" type="button" data-progress="' + player.id + '">Прогресс/инвентарь</button>';
    return html;
  }
  function renderPlayers() {
    if (!players.length) {
      playersBody.innerHTML = '<tr><td class="empty" colspan="9">Никого не найдено</td></tr>';
      return;
    }
    var html = [];
    players.forEach(function (player) {
      var nick = '<b>' + esc(player.nickname) + '</b>';
      if (player.banned) nick += '<span class="badge bad">бан</span>';
      if (player.nickname_hidden) nick += '<span class="badge">ник скрыт</span>';
      if (player.warnings > 0) {
        nick += '<span class="badge warn">предупр.: ' + player.warnings + '</span>';
      }
      if (player.ban_reason) nick += '<div class="muted small">' + esc(player.ban_reason) + '</div>';
      if (player.last_warning_reason) {
        nick += '<div class="muted small">последнее: ' + esc(player.last_warning_reason) +
          (player.last_warning_at ? ' · ' + fmtDate(player.last_warning_at) : '') + '</div>';
      }
      html.push('<tr>' +
        '<td>#' + player.id + '</td>' +
        '<td>' + nick + '</td>' +
        '<td class="small">' + esc(player.platform || '—') + '</td>' +
        '<td>' + fmtNumber(player.matches_played) + '</td>' +
        '<td class="shards" data-shards-for="' + player.id + '">' + fmtNumber(player.sky_shards) + '</td>' +
        '<td>' + fmtNumber(player.level) + '</td>' +
        '<td class="small">' + fmtDate(player.last_seen_at) + '</td>' +
        '<td>' + fmtNumber(player.reports_count) + '</td>' +
        '<td>' + playerButtons(player) + '</td>' +
        '</tr>');
    });
    playersBody.innerHTML = html.join('');
  }

  async function loadReports() {
    setStatus('загрузка…');
    var data = await getJSON('/admin/moderation/reports?status=' + encodeURIComponent(filterBox.value));
    reports = data.reports || [];
    renderReports();
    setStatus('обновлено ' + new Date().toLocaleTimeString('ru-RU'));
  }
  async function loadPlayers() {
    var query = document.getElementById('q').value.trim();
    lastQuery = query;
    var requestID = ++playersRequest;
    var path = '/admin/moderation/players?q=' + encodeURIComponent(query) +
      '&all=' + (allBox.checked ? '1' : '0') +
      '&limit=' + pageSize + '&offset=' + offset;
    var data = await getJSON(path);
    if (requestID !== playersRequest || query !== lastQuery) return;
    players = data.players || [];
    totalPlayers = typeof data.total === 'number' ? data.total : players.length;
    if (!players.length && totalPlayers > 0 && offset > 0) {
      offset = Math.max(0, Math.floor((totalPlayers - 1) / pageSize) * pageSize);
      await loadPlayers();
      return;
    }
    renderPlayers();
    updatePager();
    if (modalPlayer) {
      var refreshed = findPlayer(modalPlayer.id);
      if (refreshed) {
        modalPlayer = refreshed;
        modalTitle.textContent = 'Игрок #' + refreshed.id + ' · ' + refreshed.nickname;
        renderPlayerModal();
      }
    }
  }
  function updatePager() {
    var shown = players.length;
    var first = shown ? offset + 1 : 0;
    var last = offset + shown;
    playersCount.textContent = 'Показано ' + first + '–' + last + ' из ' + totalPlayers;
    prevButton.disabled = offset <= 0;
    nextButton.disabled = shown === 0 || offset + shown >= totalPlayers;
  }
  async function refreshAll() {
    var results = await Promise.allSettled([loadReports(), loadPlayers()]);
    results.forEach(function (result) {
      if (result.status === 'rejected') notice(result.reason && result.reason.message ? result.reason.message : 'Ошибка загрузки', true);
    });
    setStatus('обновлено ' + new Date().toLocaleTimeString('ru-RU'));
  }

  function findReport(id) {
    for (var i = 0; i < reports.length; i++) {
      if (reports[i].id === id) return reports[i];
    }
    return null;
  }
  function findPlayer(id) {
    for (var i = 0; i < players.length; i++) {
      if (players[i].id === id) return players[i];
    }
    return null;
  }

  function modalNotice(text, bad) {
    modalStatus.textContent = text;
    modalStatus.hidden = false;
    modalStatus.className = bad ? 'm-status bad' : 'm-status';
  }
  function weaponChips(player) {
    var ids = parseIDs(player.unlocked_weapons);
    if (!ids.length) return '<span class="muted">Нет</span>';
    return ids.map(function (id) {
      var label = weaponNames[id] || ('Предмет #' + id);
      return '<span class="chip">' + esc(label) +
        ' <button type="button" data-remove-weapon="' + id + '" title="Забрать">Забрать</button></span>';
    }).join('');
  }
  function renderPlayerModal() {
    if (!modalPlayer) return;
    var player = modalPlayer;
    var levels = player.char_levels || {};
    var xps = player.char_xps || {};
    var xpCards = characterOrder.map(function (key) {
      var level = parseInt(levels[key], 10) || 1;
      var xp = parseInt(xps[key], 10) || 0;
      var progress = level >= 15 ? 'максимум' : fmtNumber(xp) + ' / ' + fmtNumber(level * 1000) + ' XP';
      return '<div class="xp-card"><b>' + characterNames[key] + '</b>' +
        '<div>Уровень ' + level + '</div>' +
        '<div class="muted small">' + progress + '</div>' +
        '<div class="muted small">всего XP: ' + fmtNumber(totalXP(level, xp)) + '</div></div>';
    }).join('');
    var options = characterOrder.map(function (key) {
      return '<option value="' + key + '">' + characterNames[key] + '</option>';
    }).join('');

    modalBody.innerHTML =
      '<section class="m-section"><h3>Осколки</h3>' +
        '<div class="m-row"><b>' + fmtNumber(player.sky_shards) + '</b>' +
        '<input id="grant-shards-amount" type="number" inputmode="numeric" min="1" max="1000000" step="1" value="100" aria-label="Сколько осколков начислить">' +
        '<button class="mini primary" type="button" data-grant-shards>Начислить</button></div>' +
        '<p class="m-hint">Начисление через /admin/grant_shards, от 1 до 1 000 000 осколков.</p></section>' +
      '<section class="m-section"><h3>Опыт</h3>' +
        '<div class="xp-grid">' + xpCards + '</div>' +
        '<div class="m-row"><select id="xp-character" aria-label="Персонаж">' + options + '</select>' +
        '<input id="xp-amount" type="number" inputmode="numeric" min="1" max="105000" step="1" value="1000" aria-label="Сколько XP">' +
        '<button class="mini ok" type="button" data-grant-xp="1">+ XP</button>' +
        '<button class="mini bad" type="button" data-grant-xp="-1">− XP</button></div>' +
        '<p class="m-hint">С уровня L до L+1 нужно L×1000 XP, максимум — 15 уровень (всего 105 000 XP). Осколки за уровень не начисляются.</p></section>' +
      '<section class="m-section"><h3>Оружие и скины</h3>' +
        '<div class="chips">' + weaponChips(player) + '</div>' +
        '<div class="m-row"><button class="mini bad" type="button" data-clear-weapons>Забрать всё оружие и скины</button></div>' +
        '<p class="m-hint">Если предмет был надет, клиент снимет его сам после перезахода. Удаление идемпотентно.</p></section>';
  }
  function openPlayerModal(player) {
    modalPlayer = player;
    modalTitle.textContent = 'Игрок #' + player.id + ' · ' + player.nickname;
    modalStatus.hidden = true;
    renderPlayerModal();
    modal.hidden = false;
    document.body.classList.add('modal-open');
  }
  function closePlayerModal() {
    modal.hidden = true;
    modalPlayer = null;
    document.body.classList.remove('modal-open');
  }

  function updateShardsCell(playerID, value, added) {
    var cell = playersBody.querySelector('[data-shards-for="' + playerID + '"]');
    if (!cell) return;
    cell.innerHTML = fmtNumber(value) + ' <span class="badge ok">+' + fmtNumber(added) + '</span>';
    window.setTimeout(function () {
      if (cell.isConnected) cell.textContent = fmtNumber(value);
    }, 6000);
  }

  async function grantShards(player, rawAmount) {
    var amount = Number(rawAmount);
    if (!isFinite(amount) || Math.floor(amount) !== amount || amount < 1 || amount > 1000000) {
      modalNotice('Сумма должна быть целым числом от 1 до 1 000 000', true);
      return;
    }
    if (actionBusy) {
      modalNotice('Предыдущая операция ещё выполняется…', true);
      return;
    }
    actionBusy = true;
    try {
      var result = await postJSON('/admin/grant_shards', {player_id: player.id, amount: amount});
      var newShards = Number(result.new_shards);
      player.sky_shards = newShards;
      updateShardsCell(player.id, newShards, amount);
      if (modalPlayer && modalPlayer.id === player.id) {
        renderPlayerModal();
        var shardsBox = document.getElementById('grant-shards-amount');
        if (shardsBox) shardsBox.value = String(amount);
        modalNotice('Начислено ' + fmtNumber(amount) + '. Новый баланс: ' + fmtNumber(newShards));
      } else {
        notice('Начислено ' + fmtNumber(amount) + ' игроку #' + player.id + '. Новый баланс: ' + fmtNumber(newShards));
      }
    } catch (err) {
      modalNotice('Не удалось начислить: ' + grantErrorMessage(err), true);
    } finally {
      actionBusy = false;
    }
  }

  async function changeXP(sign) {
    if (!modalPlayer) return;
    var characterBox = document.getElementById('xp-character');
    var amountBox = document.getElementById('xp-amount');
    if (!characterBox || !amountBox) return;
    var character = characterBox.value;
    var amount = Number(amountBox.value);
    if (!isFinite(amount) || Math.floor(amount) !== amount || amount < 1 || amount > 105000) {
      modalNotice('Количество XP должно быть целым числом от 1 до 105 000', true);
      return;
    }
    if (actionBusy) {
      modalNotice('Предыдущая операция ещё выполняется…', true);
      return;
    }
    actionBusy = true;
    var player = modalPlayer;
    try {
      var result = await postJSON('/admin/moderation/players/' + player.id + '/action', {
        action: 'grant_xp',
        character: character,
        amount: amount * sign
      });
      if (result.char_levels) player.char_levels = result.char_levels;
      if (result.char_xps) player.char_xps = result.char_xps;
      var message = (sign > 0 ? 'Начислено ' : 'Списано ') + fmtNumber(amount) + ' XP · ' +
        characterNames[character] + ': уровень ' + result.level + ', XP ' + result.xp +
        ' (всего ' + fmtNumber(result.total_xp) + ')';
      if (modalPlayer && modalPlayer.id === player.id) {
        renderPlayerModal();
        var characterAfter = document.getElementById('xp-character');
        if (characterAfter) characterAfter.value = character;
        var amountAfter = document.getElementById('xp-amount');
        if (amountAfter) amountAfter.value = String(amount);
        modalNotice(message);
      } else {
        notice('Игрок #' + player.id + ': ' + message);
      }
    } catch (err) {
      modalNotice('Не удалось изменить опыт: ' + grantErrorMessage(err), true);
    } finally {
      actionBusy = false;
    }
  }

  async function removeWeapon(itemID) {
    if (!modalPlayer) return;
    var player = modalPlayer;
    var label = weaponNames[itemID] || ('предмет #' + itemID);
    if (!confirm('Забрать у #' + player.id + ' «' + player.nickname + '»: ' + label + '?')) return;
    try {
      var result = await postJSON('/admin/moderation/players/' + player.id + '/action', {
        action: 'remove_weapon',
        item_id: itemID
      });
      player.unlocked_weapons = result.unlocked_weapons || '';
      renderPlayerModal();
      modalNotice('Забрано: ' + label);
    } catch (err) {
      modalNotice('Не удалось забрать предмет: ' + grantErrorMessage(err), true);
    }
  }

  async function clearWeapons() {
    if (!modalPlayer) return;
    var player = modalPlayer;
    if (!confirm('Забрать всё оружие и скины у #' + player.id + ' «' + player.nickname + '»? Это тестовая операция.')) return;
    try {
      var result = await postJSON('/admin/moderation/players/' + player.id + '/action', {action: 'clear_weapons'});
      player.unlocked_weapons = result.unlocked_weapons || '';
      renderPlayerModal();
      modalNotice('Всё оружие и скины забраны');
    } catch (err) {
      modalNotice('Не удалось очистить инвентарь: ' + grantErrorMessage(err), true);
    }
  }

  async function resolveReport(report, action) {
    var playerId = report.player_id || 0;
    var confident = report.reported_player_id > 0 || report.nickname_matches === 1;
    if (action !== 'dismiss' && !confident) {
      var raw = prompt('Ник «' + report.reported_nickname + '» встречается у нескольких игроков. Введите player_id цели:', playerId || '');
      if (raw === null) return;
      playerId = parseInt(raw, 10);
      if (!playerId || playerId < 1) { notice('Нужен корректный player_id', true); return; }
    }
    var banReason = '';
    var actionReason = '';
    if (action === 'ban') {
      var reason = prompt('Причина бана (необязательно):', report.reason || '');
      if (reason === null) return;
      banReason = reason;
      if (!confirm('Забанить игрока #' + playerId + ' (' + report.reported_nickname + ')?')) return;
    }
    if (action === 'warn') {
      var warnReason = prompt('Причина предупреждения:', report.reason || '');
      if (warnReason === null) return;
      actionReason = warnReason;
      if (!confirm('Выдать предупреждение игроку #' + playerId + ' (' + report.reported_nickname + ')?')) return;
    }
    if (action === 'hide_nickname' && !confirm('Скрыть ник «' + report.reported_nickname + '»?')) return;
    try {
      var result = await postJSON('/admin/moderation/reports/' + report.id + '/resolve', {
        action: action,
        player_id: playerId,
        ban_reason: banReason,
        reason: actionReason
      });
      notice('Готово: ' + actionLabel(action) + (result.player_id ? ' · игрок #' + result.player_id : ''));
      await refreshAll();
    } catch (err) {
      notice(err && err.message ? err.message : 'Ошибка', true);
    }
  }

  async function actOnPlayer(player, action) {
    var banReason = '';
    var actionReason = '';
    if (action === 'ban') {
      var reason = prompt('Причина бана для «' + player.nickname + '» (необязательно):', player.ban_reason || '');
      if (reason === null) return;
      banReason = reason;
      if (!confirm('Забанить #' + player.id + ' «' + player.nickname + '»?')) return;
    }
    if (action === 'warn') {
      var warnReason = prompt('Причина предупреждения для «' + player.nickname + '»:', player.last_warning_reason || '');
      if (warnReason === null) return;
      actionReason = warnReason;
      if (!confirm('Выдать предупреждение #' + player.id + ' «' + player.nickname + '»?')) return;
    }
    if (action === 'unban' && !confirm('Снять бан с #' + player.id + ' «' + player.nickname + '»?')) return;
    if (action === 'hide_nickname' && !confirm('Скрыть ник «' + player.nickname + '»?')) return;
    try {
      await postJSON('/admin/moderation/players/' + player.id + '/action', {
        action: action,
        ban_reason: banReason,
        reason: actionReason
      });
      notice('Готово: ' + actionLabel(action) + ' · игрок #' + player.id);
      await refreshAll();
    } catch (err) {
      notice(err && err.message ? err.message : 'Ошибка', true);
    }
  }

  reportsBody.addEventListener('click', function (event) {
    var button = event.target.closest('button[data-report]');
    if (!button) return;
    var report = findReport(Number(button.getAttribute('data-report')));
    if (!report) return;
    resolveReport(report, button.getAttribute('data-report-act'));
  });
  playersBody.addEventListener('click', function (event) {
    var progressButton = event.target.closest('button[data-progress]');
    if (progressButton) {
      var progressPlayer = findPlayer(Number(progressButton.getAttribute('data-progress')));
      if (progressPlayer) openPlayerModal(progressPlayer);
      return;
    }
    var button = event.target.closest('button[data-player-act]');
    if (!button) return;
    var player = findPlayer(Number(button.getAttribute('data-player')));
    if (!player) return;
    actOnPlayer(player, button.getAttribute('data-player-act'));
  });

  modalBody.addEventListener('click', function (event) {
    if (event.target.closest('[data-grant-shards]')) {
      var shardsBox = document.getElementById('grant-shards-amount');
      if (modalPlayer) grantShards(modalPlayer, shardsBox ? shardsBox.value : '');
      return;
    }
    var xpButton = event.target.closest('[data-grant-xp]');
    if (xpButton) {
      changeXP(Number(xpButton.getAttribute('data-grant-xp')));
      return;
    }
    var removeButton = event.target.closest('[data-remove-weapon]');
    if (removeButton) {
      removeWeapon(Number(removeButton.getAttribute('data-remove-weapon')));
      return;
    }
    if (event.target.closest('[data-clear-weapons]')) {
      clearWeapons();
    }
  });
  modalBody.addEventListener('keydown', function (event) {
    if (event.key !== 'Enter') return;
    if (event.target.id === 'grant-shards-amount') {
      event.preventDefault();
      var shardsButton = modalBody.querySelector('[data-grant-shards]');
      if (shardsButton) shardsButton.click();
    } else if (event.target.id === 'xp-amount') {
      event.preventDefault();
      var xpButton = modalBody.querySelector('[data-grant-xp="1"]');
      if (xpButton) xpButton.click();
    }
  });
  document.getElementById('modal-close').addEventListener('click', closePlayerModal);
  modal.addEventListener('click', function (event) {
    if (event.target === modal) closePlayerModal();
  });
  document.addEventListener('keydown', function (event) {
    if (event.key === 'Escape' && !modal.hidden) closePlayerModal();
  });

  filterBox.addEventListener('change', function () {
    loadReports().catch(function (err) { notice(err.message, true); });
  });
  document.getElementById('reload').addEventListener('click', refreshAll);
  document.getElementById('search-form').addEventListener('submit', function (event) {
    event.preventDefault();
    offset = 0;
    loadPlayers().catch(function (err) { notice(err.message, true); });
  });
  document.getElementById('clear-search').addEventListener('click', function () {
    document.getElementById('q').value = '';
    allBox.checked = true;
    offset = 0;
    loadPlayers().catch(function (err) { notice(err.message, true); });
  });
  allBox.addEventListener('change', function () {
    offset = 0;
    loadPlayers().catch(function (err) { notice(err.message, true); });
  });
  prevButton.addEventListener('click', function () {
    offset = Math.max(0, offset - pageSize);
    loadPlayers().catch(function (err) { notice(err.message, true); });
  });
  nextButton.addEventListener('click', function () {
    offset += pageSize;
    loadPlayers().catch(function (err) { notice(err.message, true); });
  });

  if (!token) {
    notice('В адресе нет ?token=… — открой страницу по полной ссылке из ADMIN_TOKEN.', true);
  }
  refreshAll();
})();
</script>
</body>
</html>
`
