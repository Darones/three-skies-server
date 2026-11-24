package main

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"html"
	"log"
	"net"
	"net/http"
	"os"
	"sort"
	"strings"
	"sync"
	"time"
)

// Player analytics for three-skies. Mirrors the Antivirus dashboard: a
// token-protected page, platform detection and a separate bucket for junk
// traffic (VK crawlers, link previews, headless browsers) so bot launches
// never pollute the real player numbers.

type statsEvent struct {
	TS        time.Time      `json:"ts"`
	App       string         `json:"app"`
	Event     string         `json:"event"`
	PlayerID  int64          `json:"player_id"`
	Session   string         `json:"session"`
	Platform  string         `json:"platform"`
	Screen    string         `json:"screen"`
	UserAgent string         `json:"ua"`
	IsBot     bool           `json:"is_bot"`
	Payload   map[string]any `json:"payload"`
}

type statsStore struct {
	mu     sync.Mutex
	events []statsEvent
}

var stats = &statsStore{events: make([]statsEvent, 0, 4096)}

func statsToken() string {
	if value := strings.TrimSpace(os.Getenv("STATS_TOKEN")); value != "" {
		return value
	}
	return "239837"
}

func (service *api) ensureStatsTable(ctx interface{ Done() <-chan struct{} }) {
	// Kept for callers that want a synchronous check; the real work is lazy.
	_ = ctx
}

func createStatsTable(ctx interface{}) error {
	return nil
}

func initStatsTable(db *sql.DB) error {
	if db == nil {
		return nil
	}
	_, err := db.Exec(`
		CREATE TABLE IF NOT EXISTS stats_events (
			id BIGSERIAL PRIMARY KEY,
			ts TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			app TEXT NOT NULL DEFAULT 'three-skies',
			event TEXT NOT NULL,
			player_id BIGINT NOT NULL DEFAULT 0,
			session_id TEXT NOT NULL DEFAULT '',
			platform TEXT NOT NULL DEFAULT '',
			screen TEXT NOT NULL DEFAULT '',
			user_agent TEXT NOT NULL DEFAULT '',
			is_bot BOOLEAN NOT NULL DEFAULT FALSE,
			payload JSONB NOT NULL DEFAULT '{}'::jsonb
		);
		CREATE INDEX IF NOT EXISTS stats_events_ts_idx ON stats_events (ts);
		CREATE INDEX IF NOT EXISTS stats_events_event_idx ON stats_events (event);
		CREATE INDEX IF NOT EXISTS stats_events_player_idx ON stats_events (player_id);
	`)
	return err
}

func (store *statsStore) add(events ...statsEvent) {
	store.mu.Lock()
	defer store.mu.Unlock()
	for _, event := range events {
		if event.TS.IsZero() {
			event.TS = time.Now()
		}
		if event.App == "" {
			event.App = "three-skies"
		}
		store.events = append(store.events, event)
	}
	if len(store.events) > 20000 {
		store.events = store.events[len(store.events)-20000:]
	}
}

func (store *statsStore) snapshot() []statsEvent {
	store.mu.Lock()
	defer store.mu.Unlock()
	out := make([]statsEvent, len(store.events))
	copy(out, store.events)
	return out
}

func (service *api) recordStats(event statsEvent) {
	if event.TS.IsZero() {
		event.TS = time.Now()
	}
	if event.App == "" {
		event.App = "three-skies"
	}
	stats.add(event)
	db := service.db
	if db == nil || !service.dbReady.Load() {
		return
	}
	payload, _ := json.Marshal(event.Payload)
	if len(payload) == 0 {
		payload = []byte("{}")
	}
	_, err := db.Exec(
		`INSERT INTO stats_events (ts, app, event, player_id, session_id, platform, screen, user_agent, is_bot, payload)
		 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
		event.TS, event.App, event.Event, event.PlayerID, event.Session,
		event.Platform, event.Screen, event.UserAgent, event.IsBot, string(payload),
	)
	if err != nil {
		log.Printf("[stats] insert: %v", err)
	}
}

func isBotUserAgent(ua string) bool {
	lower := strings.ToLower(ua)
	markers := []string{
		"bot", "crawler", "spider", "preview", "headless", "python-requests",
		"curl/", "wget/", "facebookexternalhit", "telegrambot", "whatsapp",
		"slurp", "bingbot", "googlebot", "yandex", "ahrefs", "semrush",
		"lighthouse", "pagespeed", "vkbot", "vkshare", "ok.ru bot",
	}
	for _, marker := range markers {
		if strings.Contains(lower, marker) {
			return true
		}
	}
	return false
}

func guessPlatform(r *http.Request) string {
	ua := strings.ToLower(r.UserAgent())
	surface := ""
	if strings.Contains(r.Referer(), "vk.com") || strings.Contains(r.Referer(), "vk.ru") ||
		r.URL.Query().Get("vk_app_id") != "" || r.URL.Query().Get("vk_platform") != "" {
		surface = "VK"
	} else if strings.Contains(r.Referer(), "ok.ru") || r.URL.Query().Get("vk_client") == "ok" {
		surface = "OK"
	}
	device := "Desktop"
	if strings.Contains(ua, "iphone") || strings.Contains(ua, "ipad") || strings.Contains(ua, "ipod") {
		device = "iOS"
	} else if strings.Contains(ua, "android") {
		device = "Android"
	}
	if surface != "" {
		return surface + "/" + device
	}
	return "Web/" + device
}

func hashIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	sum := sha256.Sum256([]byte("three-skies|" + host))
	return hex.EncodeToString(sum[:8])
}

func (service *api) handleStatsEvent(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"success": false, "error": "POST only"})
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, 128<<10)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	var body struct {
		Events []statsEvent `json:"events"`
	}
	if err := decoder.Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"success": false, "error": "bad json"})
		return
	}
	if len(body.Events) > 50 {
		body.Events = body.Events[:50]
	}
	now := time.Now()
	for index := range body.Events {
		event := &body.Events[index]
		event.Event = strings.TrimSpace(event.Event)
		if event.Event == "" || len(event.Event) > 48 {
			continue
		}
		event.Platform = truncate(event.Platform, 32)
		event.Screen = truncate(event.Screen, 48)
		event.UserAgent = truncate(event.UserAgent, 256)
		event.Session = truncate(event.Session, 64)
		if event.TS.IsZero() || event.TS.After(now.Add(2*time.Minute)) || event.TS.Before(now.Add(-24*time.Hour)) {
			event.TS = now
		}
		if isBotUserAgent(event.UserAgent) {
			event.IsBot = true
		}
		service.recordStats(*event)
	}
	writeJSON(w, http.StatusOK, map[string]any{"success": true})
}

func truncate(value string, limit int) string {
	if len(value) <= limit {
		return value
	}
	return value[:limit]
}

type statsSummary struct {
	GeneratedAt   time.Time      `json:"generated_at"`
	PageViews     int            `json:"page_views"`
	JunkViews     int            `json:"junk_views"`
	VKJunkViews   int            `json:"vk_junk_views"`
	Sessions      int            `json:"sessions"`
	UniquePlayers int            `json:"unique_players"`
	Matches       int            `json:"matches"`
	OnlineNow     int            `json:"online_now"`
	Platforms     map[string]int `json:"platforms"`
	JunkPlatforms map[string]int `json:"junk_platforms"`
	Classes       map[string]int `json:"classes"`
	Results       map[string]int `json:"results"`
	Days          map[string]int `json:"days"`
	Recent        []statsEvent   `json:"recent"`
}

func summarize(events []statsEvent) statsSummary {
	now := time.Now()
	summary := statsSummary{
		GeneratedAt:   now,
		Platforms:     map[string]int{},
		JunkPlatforms: map[string]int{},
		Classes:       map[string]int{},
		Results:       map[string]int{},
		Days:          map[string]int{},
	}
	sessions := map[string]bool{}
	players := map[int64]bool{}
	online := map[string]bool{}
	for _, event := range events {
		if event.IsBot {
			summary.JunkViews++
			key := event.Platform
			if key == "" {
				key = "unknown"
			}
			summary.JunkPlatforms[key]++
			if strings.HasPrefix(key, "VK") {
				summary.VKJunkViews++
			}
		} else if event.Event == "page_view" {
			summary.PageViews++
			key := event.Platform
			if key == "" {
				key = "unknown"
			}
			summary.Platforms[key]++
		}
		if event.Session != "" {
			sessions[event.Session] = true
			if now.Sub(event.TS) <= 90*time.Second {
				online[event.Session] = true
			}
		}
		if event.PlayerID > 0 {
			players[event.PlayerID] = true
		}
		switch event.Event {
		case "match_start":
			summary.Matches++
		case "match_end":
			if value, ok := event.Payload["result"].(string); ok && value != "" {
				summary.Results[value]++
			}
		}
		if class, ok := event.Payload["class"].(string); ok && class != "" && event.Event == "session_start" {
			summary.Classes[class]++
		}
		summary.Days[event.TS.Format("2006-01-02")]++
	}
	summary.Sessions = len(sessions)
	summary.UniquePlayers = len(players)
	summary.OnlineNow = len(online)
	summary.Recent = append([]statsEvent(nil), events...)
	if len(summary.Recent) > 60 {
		summary.Recent = summary.Recent[len(summary.Recent)-60:]
	}
	// newest first
	sort.Slice(summary.Recent, func(i, j int) bool { return summary.Recent[i].TS.After(summary.Recent[j].TS) })
	return summary
}

func (service *api) loadStatsEvents(limit int) []statsEvent {
	if service.db != nil && service.dbReady.Load() {
		rows, err := service.db.Query(
			`SELECT ts, event, player_id, session_id, platform, screen, user_agent, is_bot, payload
			 FROM stats_events ORDER BY ts DESC LIMIT $1`, limit)
		if err == nil {
			defer rows.Close()
			out := make([]statsEvent, 0, limit)
			for rows.Next() {
				var event statsEvent
				var payload []byte
				if err := rows.Scan(&event.TS, &event.Event, &event.PlayerID, &event.Session,
					&event.Platform, &event.Screen, &event.UserAgent, &event.IsBot, &payload); err != nil {
					continue
				}
				event.App = "three-skies"
				_ = json.Unmarshal(payload, &event.Payload)
				out = append(out, event)
			}
			return out
		}
		log.Printf("[stats] read: %v", err)
	}
	snapshot := stats.snapshot()
	if len(snapshot) > limit {
		snapshot = snapshot[len(snapshot)-limit:]
	}
	return snapshot
}

func (service *api) handleStatsData(w http.ResponseWriter, r *http.Request) {
	if r.URL.Query().Get("token") != statsToken() {
		writeJSON(w, http.StatusForbidden, map[string]any{"success": false, "error": "forbidden"})
		return
	}
	events := service.loadStatsEvents(20000)
	writeJSON(w, http.StatusOK, summarize(events))
}

func (service *api) handleStatsPlayer(w http.ResponseWriter, r *http.Request) {
	if r.URL.Query().Get("token") != statsToken() {
		writeJSON(w, http.StatusForbidden, map[string]any{"success": false, "error": "forbidden"})
		return
	}
	id := strings.TrimSpace(r.URL.Query().Get("id"))
	if id == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"success": false, "error": "id required"})
		return
	}
	events := service.loadStatsEvents(20000)
	out := make([]statsEvent, 0, 200)
	for _, event := range events {
		if fmt.Sprintf("%d", event.PlayerID) == id {
			out = append(out, event)
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "events": out})
}

func (service *api) handleStatsReset(w http.ResponseWriter, r *http.Request) {
	if r.URL.Query().Get("token") != statsToken() {
		writeJSON(w, http.StatusForbidden, map[string]any{"success": false, "error": "forbidden"})
		return
	}
	stats.mu.Lock()
	stats.events = stats.events[:0]
	stats.mu.Unlock()
	if service.db != nil && service.dbReady.Load() {
		if _, err := service.db.Exec(`TRUNCATE stats_events`); err != nil {
			log.Printf("[stats] truncate: %v", err)
		}
	}
	http.Redirect(w, r, "/stats/dashboard?token="+statsToken(), http.StatusSeeOther)
}

func (service *api) trackGamePage(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gameRoot := r.URL.Path == "/game/" || r.URL.Path == "/game/index.html"
		vkGameRoot := r.URL.Path == "/game-vk/" || r.URL.Path == "/game-vk/index.html"
		if (gameRoot || vkGameRoot) && r.URL.Query().Get("v") == "" {
			// A VK webview can keep the old index.html with old fileSizes
			// after a redeploy. Redirect the entry point to a fresh URL so
			// the new loader (which asks the server for the real PCK size)
			// is the one that runs.
			w.Header().Set("Cache-Control", "no-store")
			prefix := "/game/"
			if vkGameRoot {
				prefix = "/game-vk/"
			}
			http.Redirect(w, r, prefix+"?v="+webBuildVersion, http.StatusFound)
			return
		}
		if gameRoot || vkGameRoot {
			ua := r.UserAgent()
			service.recordStats(statsEvent{
				Event:     "page_view",
				Platform:  guessPlatform(r),
				UserAgent: ua,
				IsBot:     isBotUserAgent(ua),
				Payload:   map[string]any{"ip": hashIP(r), "ref": truncate(r.Referer(), 200)},
			})
		}
		next.ServeHTTP(w, r)
	})
}

func (service *api) handleStatsDashboard(w http.ResponseWriter, r *http.Request) {
	if r.URL.Query().Get("token") != statsToken() {
		http.Error(w, "forbidden", http.StatusForbidden)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	fmt.Fprint(w, statsDashboardHTML(statsToken()))
}

func esc(value any) string {
	return html.EscapeString(fmt.Sprintf("%v", value))
}

func statsDashboardHTML(token string) string {
	tokenJSON, _ := json.Marshal(token)
	return `<!DOCTYPE html>
<html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Небесные осколки — статистика</title>
<style>
:root{--bg:#0a0f18;--panel:#121a27;--panel2:#0e1520;--gold:#f2c76e;--gold2:#c9963c;--text:#e9edf5;--muted:#8b97ab;--ok:#5fe08a;--bad:#ff6b6b;--blue:#6fb6ff}
*{box-sizing:border-box}
body{margin:0;background:radial-gradient(1000px 500px at 50% -10%,#1a2a44 0%,var(--bg) 55%);color:var(--text);font-family:'Segoe UI',system-ui,sans-serif}
.wrap{max-width:1280px;margin:0 auto;padding:22px 20px 60px}
h1{font-family:Georgia,serif;font-weight:600;color:var(--gold);letter-spacing:.5px;margin:0 0 4px;font-size:30px}
.sub{color:var(--muted);font-size:13px;margin-bottom:18px}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:12px;margin-bottom:18px}
.card{background:linear-gradient(180deg,var(--panel),var(--panel2));border:1px solid #22314a;border-radius:14px;padding:14px 16px}
.card .k{color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.6px}
.card .v{font-size:28px;font-weight:700;margin-top:4px}
.card.gold .v{color:var(--gold)} .card.bad .v{color:var(--bad)} .card.ok .v{color:var(--ok)} .card.blue .v{color:var(--blue)}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:14px}
@media(max-width:900px){.grid{grid-template-columns:1fr}}
.panel{background:linear-gradient(180deg,var(--panel),var(--panel2));border:1px solid #22314a;border-radius:14px;padding:14px 16px;margin-bottom:14px}
.panel h2{font-size:15px;color:var(--gold);margin:0 0 10px;font-weight:600;letter-spacing:.4px}
table{width:100%;border-collapse:collapse;font-size:13px}
th{color:var(--muted);text-align:left;font-weight:500;padding:5px 6px;border-bottom:1px solid #22314a}
td{padding:5px 6px;border-bottom:1px solid rgba(255,255,255,.04)}
tr:last-child td{border-bottom:none}
.tag{display:inline-block;padding:1px 8px;border-radius:999px;font-size:11px;background:#1b2740;color:#a9b8d0}
.tag.bot{background:#3a1620;color:#ff9aa3}
.bar{height:6px;background:#1b2740;border-radius:4px;overflow:hidden;margin-top:4px}
.bar i{display:block;height:100%;background:linear-gradient(90deg,var(--gold2),var(--gold))}
.toolbar{display:flex;gap:10px;flex-wrap:wrap;margin-bottom:14px}
button{background:#182338;color:var(--text);border:1px solid #2a3d5c;border-radius:10px;padding:8px 12px;cursor:pointer;font-size:13px}
button.danger{color:#ffb0b0;border-color:#5a2630}
#status{color:var(--muted);font-size:12px;margin-left:auto;align-self:center}
.log{font-family:Consolas,monospace;font-size:12px;color:#c7d2e5;max-height:260px;overflow:auto}
.log div{padding:2px 0;border-bottom:1px solid rgba(255,255,255,.04)}
.muted{color:var(--muted)}
a{color:var(--blue)}
</style></head><body><div class="wrap">
<h1>Небесные осколки · статистика</h1>
<div class="sub">Площадка, игроки, матчи и отдельно мусорный трафик (боты ВК, краулеры, превью ссылок)</div>
<div class="toolbar">
<button onclick="load()">Обновить</button>
<button onclick="copyJson()">Скопировать JSON</button>
<button class="danger" onclick="resetStats()">Стереть статистику</button>
<span id="status">загрузка...</span>
</div>
<div class="cards" id="cards"></div>
<div class="grid">
<div class="panel"><h2>Площадки (реальные игроки)</h2><div id="platforms"></div></div>
<div class="panel"><h2>Мусорный трафик</h2><div id="junk"></div></div>
</div>
<div class="grid">
<div class="panel"><h2>Классы</h2><div id="classes"></div></div>
<div class="panel"><h2>Исходы матчей</h2><div id="results"></div></div>
</div>
<div class="panel"><h2>Активность по дням</h2><div id="days"></div></div>
<div class="panel"><h2>Последние события</h2><div class="log" id="log"></div></div>
<script>
const TOKEN = ` + string(tokenJSON) + `;
let lastData = null;
function el(id){return document.getElementById(id)}
function esc(s){return String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
function card(label,value,cls){return '<div class="card '+cls+'"><div class="k">'+esc(label)+'</div><div class="v">'+esc(value)+'</div></div>'}
function tableRows(map, total, cls){
  const entries = Object.entries(map||{}).sort((a,b)=>b[1]-a[1]);
  if(!entries.length) return '<div class="muted">пока пусто</div>';
  const all = total || Math.max(...entries.map(e=>e[1]));
  return '<table><tr><th>Площадка</th><th>Событий</th><th style="width:40%"></th></tr>'+
    entries.map(([k,v])=>'<tr><td>'+esc(k)+'</td><td>'+v+'</td><td><div class="bar"><i style="width:'+Math.round(v/all*100)+'%"></i></div></td></tr>').join('')+'</table>';
}
async function load(){
  try{
    const r = await fetch('/stats/data?token='+encodeURIComponent(TOKEN));
    if(!r.ok) throw new Error('HTTP '+r.status);
    const d = await r.json(); lastData = d;
    el('cards').innerHTML =
      card('Игроков онлайн', d.online_now||0, 'ok')+
      card('Сессий', d.sessions||0, '')+
      card('Уникальных игроков', d.unique_players||0, 'gold')+
      card('Матчей', d.matches||0, '')+
      card('Просмотров страницы', d.page_views||0, 'blue')+
      card('Мусорный трафик', d.junk_views||0, 'bad')+
      card('Из них ВК', d.vk_junk_views||0, 'bad');
    el('platforms').innerHTML = tableRows(d.platforms, d.page_views);
    el('junk').innerHTML = tableRows(d.junk_platforms, d.junk_views);
    el('classes').innerHTML = tableRows(d.classes, 0);
    el('results').innerHTML = tableRows(d.results, 0);
    el('days').innerHTML = tableRows(d.days, 0);
    el('log').innerHTML = (d.recent||[]).map(e=>{
      const bot = e.is_bot ? ' <span class="tag bot">BOT</span>' : '';
      return '<div>'+esc(new Date(e.ts).toLocaleString())+' · <b>'+esc(e.event)+'</b>'+bot+
        ' · '+esc(e.platform||'—')+' · player '+esc(e.player_id||'—')+
        (e.screen?' · '+esc(e.screen):'')+'</div>';
    }).join('') || '<div class="muted">пока пусто</div>';
    el('status').textContent = 'обновлено '+new Date(d.generated_at).toLocaleTimeString();
  }catch(e){ el('status').textContent = 'ошибка: '+e.message; }
}
function copyJson(){ if(lastData){ navigator.clipboard.writeText(JSON.stringify(lastData,null,2)); el('status').textContent='JSON скопирован'; } }
function resetStats(){ if(confirm('Стереть всю статистику? Это необратимо.')) location.href='/stats/reset?token='+encodeURIComponent(TOKEN); }
load(); setInterval(load, 15000);
</script>
</div></body></html>`
}
