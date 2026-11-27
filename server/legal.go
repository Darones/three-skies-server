package main

// Legal pages for the store/platform review: /privacy and /terms.
//
// The pages are self-contained (inline CSS, no external assets, no scripts) so
// they work with JavaScript disabled and behind the platform iframe. They are
// served before databaseGate: a review robot must be able to read them while
// the database is down or not configured at all.
//
// Draft text, not a substitute for a lawyer. The operator is the Three Skies
// developer (a self-employed individual). The page is platform-neutral: it
// lists both communities and the support e-mail, so the same URL works for the
// VK and OK review checklists.

import (
	"fmt"
	"net/http"
	"strings"
)

const privacyPath = "/privacy"
const termsPath = "/terms"

const legalPageStyle = `
:root{--bg:#0b1018;--panel:#131c28;--line:#243349;--text:#e8eef7;--muted:#93a2b8;--gold:#f2c76e}
*{box-sizing:border-box}
body{margin:0;background:radial-gradient(1100px 460px at 50% -10%,#1a2c46 0%,var(--bg) 60%);color:var(--text);
font:15px/1.6 'Segoe UI',system-ui,Arial,sans-serif}
.wrap{max-width:840px;margin:0 auto;padding:28px 20px 64px}
.brand{color:var(--gold);font-weight:600;letter-spacing:.4px}
h1{margin:6px 0 4px;font:600 30px/1.2 Georgia,serif;color:var(--gold)}
.updated{margin:0 0 22px;color:var(--muted);font-size:13px}
.panel{background:linear-gradient(180deg,var(--panel),#0e1621);border:1px solid var(--line);border-radius:14px;padding:18px 20px}
h2{margin:22px 0 8px;font-size:16px;color:var(--gold);letter-spacing:.3px}
h2:first-child{margin-top:0}
p{margin:0 0 10px}
ul{margin:0 0 10px;padding-left:22px}
li{margin:0 0 6px}
.muted{color:var(--muted);font-size:13px}
a{color:var(--gold)}
.foot{margin-top:22px;color:var(--muted);font-size:13px}
@media (max-width:560px){.wrap{padding:18px 14px 48px}h1{font-size:24px}.panel{padding:14px 14px}}
`

const privacyPageHTML = `<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Политика конфиденциальности — Three Skies</title>
<style>` + legalPageStyle + `</style>
</head>
<body>
<div class="wrap">
<div class="brand">THREE SKIES · НЕБЕСНЫЕ ОСКОЛКИ</div>
<h1>Политика конфиденциальности</h1>
<p class="updated">Редакция от 27 ноября 2026 года</p>
<div class="panel">

<h2>1. Оператор</h2>
<p>Игру Three Skies («Небесные осколки») разрабатывает и поддерживает
Давлеев Андрей Вадимович, самозанятый (далее — «мы», «оператор»).
Мы обрабатываем данные игроков только для работы игры.</p>
<p>Связаться с оператором: <a href="mailto:daroness@ya.ru">daroness@ya.ru</a>.
Сообщества игры:
<a href="https://vk.ru/club243770009" target="_blank" rel="noopener noreferrer">ВКонтакте</a> и
<a href="https://ok.ru/group/70000062043632" target="_blank" rel="noopener noreferrer">Одноклассники</a>.</p>

<h2>2. Какие данные мы обрабатываем</h2>
<ul>
<li>идентификатор игрока в платформе, через которую выполнен вход;</li>
<li>игровой ник, выбранный персонаж, уровень и настройки;</li>
<li>игровой прогресс: осколки, покупки, инвентарь, статистика матчей;</li>
<li>сведения о платежах: факт покупки, товар, сумма и идентификатор транзакции.
Данные банковских карт мы не получаем и не храним;</li>
<li>технические данные и логи: время запросов, IP-адрес, версия клиента, ошибки.</li>
</ul>

<h2>3. Зачем мы обрабатываем данные</h2>
<ul>
<li>вход в игру и работа игрового профиля;</li>
<li>сохранение прогресса и покупок между устройствами и сессиями;</li>
<li>начисление купленных осколков и восстановление покупок;</li>
<li>модерация жалоб, борьба с читами и нарушениями правил;</li>
<li>поддержка игроков и исправление ошибок;</li>
<li>безопасность сервиса и защита от злоупотреблений.</li>
</ul>

<h2>4. Сроки хранения</h2>
<ul>
<li>профиль, ник и игровой прогресс — пока существует аккаунт;</li>
<li>логи и техническая информация — не дольше 12 месяцев;</li>
<li>записи о платежах — в срок, который требуют платёжная система и закон;</li>
<li>после удаления аккаунта профиль, прогресс, покупки и статистика удаляются,
а платёжные и статистические записи обезличиваются — см. раздел 6.</li>
</ul>

<h2>5. Кому передаются данные</h2>
<p>Мы не продаём данные игроков. Данные передаются только тем, без кого игра не работает:</p>
<ul>
<li>платформе, через которую вы входите в игру (авторизация и платежи);</li>
<li>хостинг-провайдеру, на серверах которого работает игра;</li>
<li>уполномоченным органам — если это требуется по закону.</li>
</ul>

<h2>6. Доступ и удаление</h2>
<p>Игровой профиль и связанные с ним данные можно удалить прямо в игре:
«Настройки» → «Удалить данные».</p>
<ul>
<li>удаляются профиль, игровой прогресс, покупки и статистика игрока;</li>
<li>записи о платежах сохраняются для расчётов с платформой, но обезличиваются:
идентификатор игрока в VK/OK (external_id) очищается, остаются товар, сумма
и номер заказа;</li>
<li>в статистических событиях обнуляется идентификатор игрока, очищаются идентификатор
сессии, user-agent и содержимое payload (в том числе хэш IP-адреса и источник перехода);</li>
<li>история матчей сохраняется обезличенной, без привязки к игроку;</li>
<li>жалобы, где вы были автором жалобы или игроком, на которого пожаловались, удаляются.</li>
</ul>
<p>Запросы, связанные с данными, также можно передать на
<a href="mailto:daroness@ya.ru">daroness@ya.ru</a> или в сообщество игры.
Мы отвечаем на обращения в течение 7 дней. Жалобы на ники и другой
пользовательский контент рассматриваются в течение 48 часов.</p>

<h2>7. Возраст</h2>
<p>Игра предназначена для игроков от 12 лет. Если вы младше 12 лет, играйте только с разрешения
родителей или законных представителей.</p>

<h2>8. Изменения</h2>
<p>Мы можем обновлять эту политику. Актуальная редакция всегда доступна на этой странице;
дата редакции указана в начале документа.</p>

<h2>9. Контакты</h2>
<p>Оператор: Давлеев Андрей Вадимович, самозанятый.</p>
<p>Почта: <a href="mailto:daroness@ya.ru">daroness@ya.ru</a>.<br>
Сообщества игры:
<a href="https://vk.ru/club243770009" target="_blank" rel="noopener noreferrer">ВКонтакте</a> ·
<a href="https://ok.ru/group/70000062043632" target="_blank" rel="noopener noreferrer">Одноклассники</a>.</p>
<p>Срок ответа на обращения — не более 7 дней. Жалобы на пользовательский контент
рассматриваются в течение 48 часов.</p>

<p class="foot">Документ описывает текущую версию игры и не заменяет консультацию юриста.</p>
</div>
<p class="foot">Также доступно: <a href="/terms">Пользовательское соглашение</a></p>
</div>
</body>
</html>`

const termsPageHTML = `<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Пользовательское соглашение — Three Skies</title>
<style>` + legalPageStyle + `</style>
</head>
<body>
<div class="wrap">
<div class="brand">THREE SKIES · НЕБЕСНЫЕ ОСКОЛКИ</div>
<h1>Пользовательское соглашение</h1>
<p class="updated">Редакция от 27 ноября 2026 года</p>
<div class="panel">

<h2>1. Общие положения</h2>
<p>Игра Three Skies («Небесные осколки») — многопользовательская игра, которую разрабатывает
и поддерживает Давлеев Андрей Вадимович, самозанятый (далее — «мы», «оператор»).
Начиная играть, вы соглашаетесь с этим соглашением и с правилами игры,
опубликованными в игре.</p>

<h2>2. Аккаунт</h2>
<ul>
<li>вход выполняется через аккаунт платформы, на которой запущена игра;</li>
<li>один аккаунт — один игрок; передавать аккаунт другим нельзя;</li>
<li>вы отвечаете за действия, совершённые под вашим аккаунтом.</li>
</ul>

<h2>3. Игровой процесс</h2>
<p>Игра предоставляется «как есть». Мы можем менять баланс, персонажей, оружие, режимы
и оформление, чтобы поддерживать игру в рабочем состоянии.</p>
<p>Игровые ценности (осколки, предметы, скины) не являются деньгами и не подлежат обмену
на реальные деньги вне игры.</p>

<h2>4. Покупки</h2>
<ul>
<li>покупки проходят через платёжную систему платформы;</li>
<li>осколки начисляет сервер после подтверждения платежа;</li>
<li>возврат средств выполняется по правилам платформы и применимого закона.</li>
</ul>

<h2>5. Правила поведения и пользовательский контент</h2>
<p>Ник — единственный пользовательский контент в игре. Требования к нику:</p>
<ul>
<li>длина от 3 до 32 символов;</li>
<li>запрещены мат и оскорбления, выдача себя за других игроков, администрацию
или разработчиков, реклама и ссылки.</li>
</ul>
<p>Запрещены читы, сговор, намеренное использование ошибок игры, обход блокировок
и любые действия, которые мешают другим игрокам.</p>
<p>Жалобы отправляются кнопкой «!» в бою или формой жалобы в лобби.
Каждую жалобу модератор рассматривает в течение 48 часов.</p>
<p>Меры: предупреждение, скрытие ника, блокировка аккаунта. Мера зависит от нарушения
и повторов. Если вы не согласны с решением, напишите в сообщество игры — апелляцию
рассмотрит модератор.</p>

<h2>6. Боты</h2>
<p>Когда живых игроков не хватает или игрок вышел, его место может занять бот.
Боты всегда помечены на экране загрузки и в итогах боя; мы не выдаём их за живых игроков.</p>

<h2>7. Ответственность</h2>
<p>Мы стараемся, чтобы игра работала стабильно, но не гарантируем непрерывную работу
сервиса: возможны технические работы, сбои связи и обновления. Мы не отвечаем за сбои
на стороне платформы, интернет-провайдера или устройства игрока.</p>
<p>За нарушение соглашения или правил игры мы можем ограничить доступ к аккаунту.</p>

<h2>8. Изменения соглашения</h2>
<p>Мы можем обновлять соглашение. Актуальная редакция всегда доступна на этой странице;
дата редакции указана в начале документа. Продолжая играть после обновления, вы
принимаете новую редакцию.</p>

<h2>9. Контакты</h2>
<p>Оператор: Давлеев Андрей Вадимович, самозанятый.</p>
<p>Почта: <a href="mailto:daroness@ya.ru">daroness@ya.ru</a>.<br>
Сообщества игры:
<a href="https://vk.ru/club243770009" target="_blank" rel="noopener noreferrer">ВКонтакте</a> ·
<a href="https://ok.ru/group/70000062043632" target="_blank" rel="noopener noreferrer">Одноклассники</a>.</p>
<p>Срок ответа на обращения — не более 7 дней. Жалобы на пользовательский контент
рассматриваются в течение 48 часов.</p>

<p class="foot">Документ описывает текущую версию игры и не заменяет консультацию юриста.</p>
</div>
<p class="foot">Также доступно: <a href="/privacy">Политика конфиденциальности</a></p>
</div>
</body>
</html>`

// legalRoutes serves the public legal pages before databaseGate, so they stay
// readable while the database is unavailable.
func legalRoutes(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		path := r.URL.Path
		if path == privacyPath+"/" || path == termsPath+"/" {
			// Keep one canonical URL for store review checklists.
			http.Redirect(w, r, strings.TrimSuffix(path, "/"), http.StatusMovedPermanently)
			return
		}
		var page string
		switch path {
		case privacyPath:
			page = privacyPageHTML
		case termsPath:
			page = termsPageHTML
		default:
			next.ServeHTTP(w, r)
			return
		}
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			w.Header().Set("Allow", "GET, HEAD")
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Header().Set("Content-Language", "ru")
		w.Header().Set("Cache-Control", "public, max-age=300")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "SAMEORIGIN")
		w.Header().Set("Content-Security-Policy",
			"default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; img-src 'self' data:")
		if r.Method == http.MethodHead {
			return
		}
		fmt.Fprint(w, page)
	})
}
