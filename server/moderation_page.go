package main

// moderationPageHTML is a single self-contained admin page: no build step, no
// external assets. The admin token stays in the page URL and is appended to
// every fetch call by JS; the server injects nothing into this file.
const moderationPageHTML = `<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<title>Модерация ников — Небесные осколки</title>
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
table{border-collapse:collapse;width:100%;min-width:900px}
th,td{padding:8px 10px;text-align:left;vertical-align:top;border-bottom:1px solid #1d293b}
th{position:sticky;top:0;background:#172231;color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.5px;font-weight:600;z-index:1}
tr:last-child td{border-bottom:0}
tbody tr:hover{background:#16202e}
.muted{color:var(--muted)}
.small{font-size:12px}
.reason{min-width:180px;max-width:320px;white-space:pre-wrap;word-break:break-word}
button{font:inherit;color:var(--text);background:#1d2a3c;border:1px solid #2d3f58;border-radius:8px;padding:5px 10px;cursor:pointer}
button:hover{background:#26374e}
button.primary{background:#274469;border-color:#3a6090}
button.mini{padding:3px 8px;font-size:12px;margin:1px}
button.ok{border-color:#2f6b4a;color:#bdf3d2}
button.warn{border-color:#7a5a24;color:#ffe1ab}
button.bad{border-color:#7d3232;color:#ffc2c2}
input,select{font:inherit;color:var(--text);background:#0f1824;border:1px solid #2d3f58;border-radius:8px;padding:5px 9px}
.badge{display:inline-block;margin-left:6px;padding:1px 7px;border-radius:999px;border:1px solid #3b4d68;color:var(--muted);font-size:11px;vertical-align:middle}
.badge.bad{border-color:#7d3232;color:#ffb4b4}
.badge.warn{border-color:#7a5a24;color:#ffd99b}
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
      <h1>Модерация ников <span class="brand">Небесные осколки</span></h1>
      <p class="sub">Личная страница владельца. Жалобы из игры и управление никами. Ссылка нигде в игре не публикуется.</p>
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
      <form id="search-form">
        <input id="q" type="search" placeholder="часть ника" autocomplete="off" maxlength="64">
        <button type="submit">Найти</button>
        <button type="button" id="clear-search">Сбросить</button>
      </form>
    </div>
    <div class="table-wrap">
      <table>
        <thead><tr>
          <th>ID</th><th>Ник</th><th>Платформа</th><th>Матчи</th>
          <th>Последний вход</th><th>Жалоб</th><th>Действия</th>
        </tr></thead>
        <tbody id="players"><tr><td class="empty" colspan="7">Загрузка…</td></tr></tbody>
      </table>
    </div>
    <p class="foot muted">Без поиска показываются забаненные, скрытые, недавно заходившие и те, на кого жаловались.</p>
  </section>
</div>
<script>
(function () {
  'use strict';
  var token = new URLSearchParams(location.search).get('token') || '';
  var reports = [];
  var players = [];
  var lastQuery = '';

  var noticeBox = document.getElementById('notice');
  var statusBox = document.getElementById('status');
  var reportsBody = document.getElementById('reports');
  var playersBody = document.getElementById('players');
  var filterBox = document.getElementById('filter');

  function esc(value) {
    return String(value === null || value === undefined ? '' : value).replace(/[&<>"']/g, function (ch) {
      return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch];
    });
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
      unban: 'бан снят'
    };
    return labels[action] || action;
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
    var response = await fetch(apiUrl(path), {
      method: 'POST',
      credentials: 'same-origin',
      headers: {'Content-Type': 'application/json'},
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
    return html;
  }
  function renderPlayers() {
    if (!players.length) {
      playersBody.innerHTML = '<tr><td class="empty" colspan="7">Никого не найдено</td></tr>';
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
        '<td>' + player.matches_played + '</td>' +
        '<td class="small">' + fmtDate(player.last_seen_at) + '</td>' +
        '<td>' + player.reports_count + '</td>' +
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
    var data = await getJSON('/admin/moderation/players?q=' + encodeURIComponent(query));
    if (query !== lastQuery) return;
    players = data.players || [];
    renderPlayers();
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
    var button = event.target.closest('button[data-player-act]');
    if (!button) return;
    var player = findPlayer(Number(button.getAttribute('data-player')));
    if (!player) return;
    actOnPlayer(player, button.getAttribute('data-player-act'));
  });

  filterBox.addEventListener('change', function () {
    loadReports().catch(function (err) { notice(err.message, true); });
  });
  document.getElementById('reload').addEventListener('click', refreshAll);
  document.getElementById('search-form').addEventListener('submit', function (event) {
    event.preventDefault();
    loadPlayers().catch(function (err) { notice(err.message, true); });
  });
  document.getElementById('clear-search').addEventListener('click', function () {
    document.getElementById('q').value = '';
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
