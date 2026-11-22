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

Обновлено: **22.11.2026, вечер**. Это память для следующих сессий: читать до любых правок.

## Где игра живёт сейчас

- **Production:** `https://three-skies-server.relaxdev.ru/game/`
- Игра **полностью лежит на RelaxDev**: Go-сервер, WebSocket, PostgreSQL и веб-сборка (PCK + wasm) отдаются с этого домена. GitHub Pages больше не источник игры — только редирект на RelaxDev.
- Проверка: `GET /health` → `status=ok`, `database=ok`; `GET /game/index.pck` → актуальный `Content-Length`.
- Деплой: пуш в `origin/main` → RelaxDev пересобирает и перезапускает. Иногда нужен пустой commit для повторного деплоя. После деплоя проверять uptime в `/health` и размер PCK, а не верить пушу.
- **Текущий прод (на 22.11.2026, вечер):**
  - PCK: сборка `index_20261122_230206.pck`, на хосте `index.pck`, **45 933 616 байт**
    (HP Оболочки у хоста + решающая Оболочка в sudden death).
  - `main`: `3e3659c` (билд + серверный фикс); контейнер перезапущен, `/health` ok.
  - Исходники: ветка `mobile-ui`, `3b256ce` (`fix: host shell HP sync and decisive shell in sudden death`).
  - Сервер: `server/ws.go` + `server/web/index.pck` в `main`.

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

### Сервер и сеть

- Сервер — источник времени матча; клиент синхронизирует `match_time` по `match_time_left_ms`.
- Сервер владеет HP/смертью Оболочки, кристаллом, счётом, наградами.
- Исправлены: сброс `shellSpawnID` при смене хоста, ульта мага (`ult_lightning_storm`), сигнатура `SkyShell.take_damage`, анимации удалённых людей, арбалетчица (только арбалет), иконка тёмной фракции.

### Веб и звук

- PCK на вебе грузится range-кусками с `cache: 'no-store'`; иначе браузер смешивал старый PCK с новым («Game data is incomplete»).
- Боевая музыка (72 с) зациклена и перезапускается при `state = "live"`.
- При потере фокуса/сворачивании мини-приложения Master-шина глушится, при возврате восстанавливается; в `_exit_tree` музыка и эмбиент останавливаются.
- Тёмная иконка фракции — `assets/ui/teams/dark_team.png`; баннер «×2 награды» опущен в центр; мобильная кнопка паузы убрана.

## Что проверено

- **Полный матч на финальной сборке `213705` (prod, 22.11 вечер):** Оболочка
  появилась на **2:00/4:00/6:00/8:00** (`spawn t=120.0/240.0/360.0/480.0`),
  жила 12–15 с, смерть — серверным событием, «исчезновения через 1 с» нет.
  Боты били её вместе с игроком (интенты от `-2…-6` и игрока), 0 `SCRIPT ERROR`.
- **Фикс HP хоста:** `TestShellStateEchoKeepsSpawnID` (падал до, проходит после);
  9-минутный QA-бой — HP Оболочки падал 723→584→494→324, спавны 120/240/360/480.
- **Решающая Оболочка в sudden death:** QA-бой с форсированным sudden death —
  спавн, смерть, осколок, доставка, `begin match result`.
- **Экран результатов:** реальный переход после осколка (1:0), полный кадр
  пробником — `docs/qa-results-probe-stats.png`, `docs/qa-results-probe-players.png`.
- **После деплоя 3e3659c:** `/health` uptime сбросился, `/game/index.pck` =
  45 933 616, `fileSizes` совпадает, веб-лобби грузится без «Game data is incomplete».
- 10 QA-боёв (6 с одним человеком + боты, 4 с двумя людьми) — 0 `SCRIPT ERROR`.
- **3 онлайн-боя 1v1** (по 2 живых сетевых клиента, разные классы: Воин+Маг, Маг+Арбалетчица, Арбалетчица+Воин), матчи по 10 минут. В каждой комнате Оболочка появилась на **2:00, 4:00, 6:00, 8:00**; в 6 логах 0 ошибок.
- **Production-веб:** Оболочка появилась в 2:00, прожила полное 45-секундное окно, видна на экране. Скриншот: `docs/qa-web-shell-2min.jpg`.
- `go test ./...` проходит, в т.ч. `TestBotDamageAppliesToShell`, `TestShellStateEchoKeepsSpawnID`.

## Что не проверено / риски

- Полные 8 минут на **новой** сборке `230206` (с фиксами HP и sudden death) не
  перепрогонялись на проде: 8-минутный прогон был на `213705`, фиксы проверены
  9-минутным QA-боем и юнит-тестами.
- Sudden death на проде вживую не проверялся (только форсированный QA-стенд).
- Залипшая комната поиска не воспроизвелась: два живых клиента попали в одну
  комнату 2/6 и матч стартовал. Отдельного фикса по-прежнему нет.
- На этой машине **оконные** клиенты Godot сами завершаются на 4–6 минуте без
  ошибок в логе и без событий Windows; headless-клиент стабильно живёт 12+ минут.
  Монитор 540×1124, окно обрезается — похоже на среду/драйвер, не на игру.
- Windows EXE: нет шаблонов экспорта (web-шаблоны есть, windows-шаблонов 4.7.2 нет).
  VK-платежи/реклама/аналитика: **пока не внедряем** — см. правило 6 ниже.
- Локальный QA-сервер без БД пишет `pq: SSL is not enabled` — это только стенд, production БД работает.
- Мелочь на экране результатов: на вкладке «Игроки» опыт 98 против 83 на
  «Статистике» (похоже, обновляется после начисления).

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

