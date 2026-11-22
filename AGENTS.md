<!-- summer-engine:start. summer setup updates only this block; write your own notes outside it. -->
# Summer Engine game

This is a game made with Summer Engine, the game engine built for AI. Game code is GDScript (`.gd`), scenes are `.tscn`, resources are `.tres`, and `project.godot` is the project file.

## First game: make it look finished

People judge Summer by the first frame of their first game, so make it look finished even when they ask for a quick prototype. Keep the features they asked for and raise the look:
- sky and sun with shadows, tonemapping, a little fog;
- a texture on every surface, and real models for the player, characters and main props (the starter project and the Summer asset library first), never capsules or boxes as final art;
- one colour palette and a styled UI font.
Before you say it is ready, play it and look at a screenshot of the running game, not the editor: the editor shows a preview sky and sun that the game does not have.

## How to work on it

- Write GDScript (`.gd`) files directly. Create and change scenes and import assets through Summer while Summer Engine has the project open: it imports new files, and the editor rewrites `.tscn` files when it saves, so hand edits to an open scene get lost.
- With Summer's MCP server, use the `summer_*` tools; `summer_get_project_context` tells you which project you are connected to. Without it, run the same operations as `summer` commands in the shell (the `summer-cli` skill). If `summer` is missing or older than 4.0, use `npx -y summer-engine@latest` in its place.
- Summer's skills teach each part of a game. `npx -y summer-engine@latest setup <agent> --yes` installs them for your agent (add `--cli` for no MCP server). Start with `using-summer`, and find the right one with `summer docs search --query "<the task>"`.
- `.summer/` is the project's memory: `GameSoul.md` says what the game is, `memory/` holds the decisions to keep. Read them before you change the game's look, sound or story.
- Check your own work: script errors, a screenshot, a play run. Ask the person to play only for feel and fun.

## The five commands

1. `summer run .` opens the project in Summer Engine. An agent's run stays in the background.
2. `summer engine get-project-context` (MCP: `summer_get_project_context`) reads the project, its main scene and the engine version. Run it first.
3. `summer engine play`, then `summer engine get-diagnostics` (MCP: `summer_play`, `summer_get_diagnostics`), runs the game and reads its errors. `summer engine stop` (`summer_stop`) ends it.
4. `summer engine screenshot` (MCP: `summer_screenshot`) saves an image of the editor or the running game. Open its `localPath` to look.
5. `summer ops search "<what you want>"` (MCP: `summer_search`) finds any other operation. Run it as `summer <area> <action>` (MCP: `summer_call`), with `--dry-run` first for a change.

## Publishing

The `publish-your-game` skill has the steps; `summer ops search "publish my game"` finds each operation. Going live needs the game owner's yes. A game goes live as soon as Summer's automated checks pass; Summer's staff review it after it is live, so never tell anyone to wait for a review.
<!-- summer-engine:end -->

---

# Состояние проекта «Небесные осколки» (three-skies)

Обновлено: **23.11.2026, ночь**. Это память для следующих сессий: читать до любых правок.

## Где игра живёт сейчас

- **Production:** `https://three-skies-server.relaxdev.ru/game/`
- Игра **полностью лежит на RelaxDev**: Go-сервер, WebSocket, PostgreSQL и веб-сборка (PCK + wasm) отдаются с этого домена. GitHub Pages больше не источник игры — только редирект на RelaxDev.
- Проверка: `GET /health` → `status=ok`, `database=ok`; `GET /game/index.pck` → актуальный `Content-Length`.
- Деплой: пуш в `origin/main` → RelaxDev пересобирает и перезапускает. Иногда нужен пустой commit для повторного деплоя. После деплоя проверять uptime в `/health` и размер PCK, а не верить пушу.
- **Текущий прод (на 23.11.2026, ночь):**
  - PCK: сборка `index_20261123_004347.pck`, на хосте `index.pck`, **45 871 068 байт**
    (мобильный UI, стелс, боты, база, статистика).
  - `main`: `2431511` (сервер + PCK); контейнер перезапущен, `/health` ok.
  - Исходники: ветка `mobile-ui` (`ddc8d9d` + фикс времени статистики; см. `git log`).
  - Сервер: `server/ws.go`, `server/main.go`, `server/stats.go` + `server/web/index.pck` в `main`.
  - Дашборд: `https://three-skies-server.relaxdev.ru/stats/dashboard?token=239837`.

## Что уже сделано

### Оболочка (главная боль)

- Расписание **2:00 / 4:00 / 6:00 / 8:00** считается от **серверного** `match_time`, а не от локальной загрузки сцены. На вебе сцена грузится позже `match_start`; раньше из-за этого первый спавн уезжал на 3:00+, дальше 5:00/7:00/9:00.
- Если сцена загрузилась уже после границы, но 45-секундное окно ещё открыто — Оболочка появляется сразу, а не ждёт следующие 2 минуты.
- `shell_state` со старым `spawn_id` (включая `0`) игнорируется. Это был тот самый «взрыв на 1 секунду»: stale `alive=false` приходил после спавна и прятал новую Оболочку.
- Смена хоста сбрасывает `shellSpawnID` на сервере; новый хост ждёт следующую границу.
- **Боты снова дерутся за Оболочку.** Ранее я по ошибке запретил им выбирать её целью и отклонял их урон на сервере. Это откатано 22.11: боты, как и игроки, идут к Оболочке и бьют её (`TestBotDamageAppliesToShell`). Смысл игры — драка за осколок, а не PvE только для человека.
- **HP Оболочки у хоста (22.11, вечер).** Сервер в эхе `shell_state` присылал `spawn_id=0`;
  клиент отбрасывает пакеты со старым id, поэтому у хоста полоска стояла на full HP.
  Теперь сервер кладёт в эхо `room.shellSpawnID` (`TestShellStateEchoKeepsSpawnID`), а хост
  не берёт из эха `phase/timer` — расписание 2/4/6/8 остаётся его, из эха идут только
  `alive/hp`. Проверено 9-минутным QA-боем: `S hp=723 → 584 → 494 → 324`.
- **Решающая Оболочка в sudden death (22.11, вечер).** При равном счёте на 10:00
  клиент спавнит одну Оболочку сразу; сервер завершает матч на первой доставке
  (`handleCrystalDeliver`, ветка `room.suddenDeath`). Раньше 2 минуты не было
  ни Оболочки, ни осколка, и победитель выбирался случайно. Проверено QA-боем
  с форсированным sudden death: спавн → смерть → осколок → доставка → результат.

### Мобильный UI и статистика (23.11, ночь)

- **iOS-раскладка.** `ui_layout.gd` классифицирует элементы по эталону 844×390,
  а не по фактической ширине экрана: на длинном iPhone счёт/скиллы больше не
  уезжают в центр.
- **Джойстик** видим на всех мобилах (убрана прозрачность, усилены база/кнопка).
- **Стан:** баннер «ОГЛУШЕНИЕ» в HUD + кольцо и надпись «СТАН» над героем.
- **Инвентарь:** колонки 0–35 / 37–63 / 65–100%, карточки оружия в одну колонку
  с прокруткой; кнопка «Сменить ник» и вкладки статистики помещаются.
- **Спиннер поиска** — нарисованное кольцо вместо символа `◌` (его не было в
  шрифте, на телефоне рисовался цифрой/квадратом).
- **Смена ника:** на вебе пробуем системную клавиатуру через HTML-поле;
  наша экранная клавиатура остаётся фолбэком.
- **Статистика:** серверные `/stats/event`, `/stats/data`, `/stats/dashboard`,
  `/stats/player`, `/stats/reset` (токен 239837). Клиентский автолоад `Stats`
  шлёт session_start, heartbeat, match_start, match_end. Площадка (VK/OK,
  iOS/Android/Desktop) и мусорный трафик (боты ВК, краулеры, превью) считаются
  отдельно. Проверено живым клиентом: session_start с классом и платформой.
  Важно: время события ставит сервер; клиент `ts` не шлёт.
- **Ник и player_id** зеркалятся в localStorage на вебе.

### Стелс, боты, база (23.11, ночь)

- Убран инвиз от колонн: `PillarCollision` больше не блокирует обзор.
- Кусты сдвинуты к центру ~2x, зона 3.9 м, 7 кустов в кластере.
- В кустах автоатака не работает; скилл, урон и враг в 5 м раскрывают;
  союзники видят всегда; носильщик осколка всегда виден.
- Боты не выбирают скрытую цель; ульта мага не бьёт скрытых. Бот ищет куст,
  только если видел вход с 10 м (память 2.5 с).
- Союзные боты сопровождают носильщика, атакуют угрозу рядом, не фармят.
  Думают реже, есть задержка смены цели, убрано дёрганье.
- Фонтан/лавка: NavigationObstacle3D + steering-отталкивание.
- База: 100 HP/с после 3 с стояния; урон сбрасывает таймер, уход с базы
  сбрасывает; 5 с защиты после респавна; врагов выталкивает из купола.
- Респавн ботов: 2 с защиты от старых `alive=false`, нулевой HP не убивает
  только что возрождённого (лечит цикл «респавн → смерть»).


- Сервер — источник времени матча; клиент синхронизирует `match_time` по `match_time_left_ms`.
- Сервер владеет HP/смертью Оболочки, кристаллом, счётом, наградами.
- Исправлены: сброс `shellSpawnID` при смене хоста, ульта мага (`ult_lightning_storm`), сигнатура `SkyShell.take_damage`, анимации удалённых людей, арбалетчица (только арбалет), иконка тёмной фракции.

### Веб и звук

- PCK на вебе грузится range-кусками с `cache: 'no-store'`; иначе браузер смешивал старый PCK с новым («Game data is incomplete»).
- Боевая музыка (72 с) зациклена и перезапускается при `state = "live"`.
- При потере фокуса/сворачивании мини-приложения Master-шина глушится, при возврате восстанавливается; в `_exit_tree` музыка и эмбиент останавливаются.
- Тёмная иконка фракции — `assets/ui/teams/dark_team.png`; баннер «×2 награды» опущен в центр; мобильная кнопка паузы убрана.

## Что проверено

- **23.11, ночь: 3 онлайн-боя** на QA-стенде — 2 живых + боты, 4 живых + боты,
  6 живых (3 на 3). У всех клиентов **0 `SCRIPT ERROR`**; циклов
  «бот респавнится и сразу умирает» нет (0 за ≤3 с); Оболочка спавнится и
  умирает серверным событием, осколок доставляется.
- **UI-аудит мобильный 2000×690:** инвентарь (колонки, прокрутка карточек),
  спиннер поиска (нарисованное кольцо), настройки, лобби. Исправлены наложения
  колонок инвентаря и обрезка карточек/вкладок; спиннер больше не цифра.
- **Статистика:** живой клиент отправил `session_start` (класс, платформа);
  `/stats/dashboard?token=239837` → 200; мусорный трафик считается отдельно.
- **После деплоя `2431511`:** `/health` uptime сбросился, `/game/index.pck` =
  45 871 068, прод-страница грузится без `SCRIPT ERROR`.
- **Полный матч на финальной сборке `213705` (prod, 22.11 вечер):** Оболочка
  появилась на **2:00/4:00/6:00/8:00** (`spawn t=120.0/240.0/360.0/480.0`),
  жила 12–15 с, смерть — серверным событием, «исчезновения через 1 с» нет.
  Боты били её вместе с игроком, 0 `SCRIPT ERROR`.
- **Фикс HP хоста:** `TestShellStateEchoKeepsSpawnID`; 9-минутный QA-бой —
  HP Оболочки падал 723→584→494→324, спавны 120/240/360/480.
- **Решающая Оболочка в sudden death:** QA-бой с форсированным sudden death —
  спавн, смерть, осколок, доставка, `begin match result`.
- **Экран результатов:** реальный переход после осколка (1:0), полный кадр
  пробником — `docs/qa-results-probe-stats.png`, `docs/qa-results-probe-players.png`.
- 10 QA-боёв (6 с одним человеком + боты, 4 с двумя людьми) — 0 `SCRIPT ERROR`.
- **3 онлайн-боя 1v1** (по 2 живых клиента, разные классы) — Оболочка на
  2:00/4:00/6:00/8:00, 0 ошибок.
- `go test ./...` проходит, в т.ч. `TestBotDamageAppliesToShell`, `TestShellStateEchoKeepsSpawnID`.

## Что не проверено / риски

- **Реальный iPhone** после ночных правок не проверялся: у Андрея нет телефона
  под рукой, тестил брат. Нужен его тест раскладки, джойстика, стана и клавиатуры.
- Полный 10-минутный матч на новой сборке не перепрогонялся: ночные бои были
  по 165 с; спавны/смерти/доставка проверены, но не все 2/4/6/8.
- Магазин на мобиле: функционален, но остаётся много пустого места и кнопка
  «Купить осколки» у верхней границы — косметика.
- Лобби: свечение выбранной карточки героя заходит на соседние карточки; это
  ручная раскладка из UI-редактора, не менял, чтобы не сломать тюнинг.
- Дашборд только запущен: реальный трафик/боты ВК ещё не накоплены.
- Sudden death на проде вживую не проверялся (только QA-стенд).
- Залипшая комната поиска не воспроизвелась; отдельного фикса нет.
- Windows EXE: нет шаблонов экспорта. VK-платежи/реклама: **не внедряем**.
- Локальный QA-сервер без БД пишет `pq: SSL is not enabled` — только стенд.

## Правило на будущее (важно)

Проблема с Оболочкой тянулась **3–4 дня**. За это время было много гипотез, лишних правок и хождение по кругу; часть изменений (боты) была не по делу, потому что я цеплялся за старые логи вместо текущего симптома пользователя.

Если ситуация повторяется — **несколько попыток подряд не дают результата, гипотезы ходят по кругу, я снова начинаю менять геймплей без просьбы** — нужно остановиться и прямо написать пользователю:

> «Надо начать новый чат: ИИ затупил и не может решить это уже который раз. Вот короткий бриф текущего состояния, чтобы новый чат продолжил с места, а не с нуля».

В новом чате дать короткий бриф: проект, прод-URL, текущий PCK/коммит, что уже исправлено, что проверено, что не трогать.

## Как работать, чтобы не повторять

1. Сначала доказательство: лог, скриншот, таймстемп, размер файла. Потом правка.
2. Не менять геймплей (боты, баланс, поведение целей) без просьбы пользователя или лога, который прямо это подтверждает.
3. Несколько независимых фиксов — по одному, с проверкой после каждого.
4. После деплоя проверять прод: `/health` uptime, `Content-Length /game/index.pck`, HTML `fileSizes`; не считать пуш доказательством.
5. Держать этот файл в актуальном состоянии: версии, URL, что проверено, что осталось.
6. **Платежи, рекламу и SDK (VK/OK/Яндекс) пока не внедряем.** Решение Андрея
   (22.11.2026): сначала чистая игра без сторонних SDK, внедряем их позже и сразу
   все. Не добавлять в код вызовы оплаты/рекламы, не просить ключи и токены,
   не подключать `/vk/pay`, `/ok/pay` и счётчики аналитики до отдельной задачи.

