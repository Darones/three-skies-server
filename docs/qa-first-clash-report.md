# Первая стычка: фриз после WarmupFlow — причина и правка (26.11.2026)

Ничего не коммитилось и не деплоилось. Правки только в `scripts/game.gd`
и новых QA-файлах `tools/first_clash_probe.gd` / `tools/FirstClashProbe.tscn`.
`scripts/warmup_flow.gd`, `scripts/loading_screen.gd`, `scripts/network_manager.gd`,
`scripts/remote_player.gd`, `server/*`, `shaders/*`, `scripts/hero.gd` не менялись.

---

## 1. Короткий вывод

Первый удар после полного WarmupFlow всё равно фризил **не из-за загрузки ассетов
и не из-за звука/шрифта**: кадр целиком уходил в рендер (компиляция pipeline),
а `process` в этом кадре был < 3 мс.

Причина: `WarmupFlow` рисует VFX и Label3D в **своём скрытом SubViewport с
`own_world_3d = true`**. На Compatibility (а именно он используется в веб-сборке
ВК/ОК) это **другой pipeline state**, чем у боевого вьюпорта: другое окружение
(туман/свет), другой depth-режим у damage-number Label3D. Поэтому в первом
кадре стычки драйвер всё равно компилировал:

| Что не было прогрето по-настоящему | Первый кадр (Compatibility, warmup=true) |
|---|---|
| сцена удара `vfx_hit_01/02`, `impact_01/02`, `big_impact_01/02` | **61.7 мс** (render 60.0, process 2.1) |
| damage number `Label3D` (`no_depth_test = true`, outline 12, font 64) | **80.4 мс** (render 78.8, process 2.4) |
| первый ульт (пулы burst/ring, `lightning_strike_fx`, трещины `earthquake_fx`) | **61.6 мс** (в одном прогоне до **334.7 мс**, если до этого не успел скастовать бот) |
| полная первая стычка (атака + VFX + число + burst) | **62.7 мс** (render 62.1, process 3.5) |
| мобильный профиль 844×390 + Compatibility | **70.8 мс** |

На Forward+ (нативный десктоп) первая стычка уже была ~9 мс; там заметен только
первый ульт (~52 мс в прошлом аудите). То есть жалоба «фриз в первой стычке» —
это прежде всего **веб/Compatibility** и мобильный веб.

Правка: один раз при `_ready`, пока висит панель выбора класса, прогревать
hot-ассеты **в реальном World3D матча** (`own_world_3d = false`), в скрытом
SubViewport с камерой на `y = -100`. `start_match` ждёт окончания прогрева
уже после спавна героев и до `state = "live"`.

| Конфиг | Было (WarmupFlow, без правки) | Стало | Кадры > 33 мс |
|---|---|---|---|
| desktop 1440×734 high, Forward+ | 9.4 мс | **6.6–8.1 мс** | 0 → 0 |
| desktop 1440×734 low, Forward+ | 7.2 мс | **7.7 мс** | 0 → 0 |
| desktop 1440×734 high, **Compatibility** | **62.7 мс** | **13.2–18.8 мс** | 1 → **0** |
| desktop 1440×734 low, Compatibility | — | **10.7 мс** | 0 |
| mobile 844×390 low, Forward+ | 9.9 мс | **7.0–9.3 мс** | 0 → 0 |
| mobile 844×390 low, **Compatibility** | **70.8 мс** | **6.6–7.5 мс** | 1 → **0** |
| первый ульт, Compatibility | 61.6–334.7 мс | **15.4 мс** | 2 → **0** |
| первый kill (VFX + kill feed), Compatibility | — | **14.7 мс** | 0 |

Полный прогрев занимает **0.55–0.92 с** (на Forward+ ~0.6 с, Compatibility
~0.7–0.9 с) и целиком идёт за панелью выбора класса; `start_match → live`
вырос с 276–344 мс до 435–665 мс, но это не фриз в бою.

---

## 2. Чем измеряли

Новый пробник `tools/FirstClashProbe.tscn` (`tools/first_clash_probe.gd`):

- запускает настоящий `Main.tscn` + `start_match(WARRIOR, 0)` с ботами;
- ждёт `state == "live"`, затем в известный момент (по умолчанию +300 мс)
  телепортирует игрока к первому врагу в центр арены (вне base shield) и
  вызывает штатный `_try_auto_attack`; для `clash` через 160 мс бьёт и враг;
- пишет по кадрам: wall time (`Time.get_ticks_usec`), **раздельно `process` и
  `render`** (сигнал `SceneTree.process_frame` + последний `_process` пробника,
  `process_priority = 1000`), `Performance.TIME_PROCESS/TIME_PHYSICS_PROCESS`,
  nodes/resources/draw calls/VRAM, `RenderingServer.get_frame_setup_time_cpu()`,
  счётчики `PIPELINE_COMPILATIONS_*` (если движок их отдаёт);
- ловит первые события: удар, VFX, звук, damage number, kill, kill feed, спавн
  бота, каст (`CombatProfiler.mark(...)` + опрос здоровья/аудио/лейблов);
- режимы для изоляции подсистем: `--action=clash|attack|hit|vfx|number|ability|kill`;
- `--warm` / `--no-warm` (реальный WarmupFlow), `--skip-clash-warm` — A/B-контроль
  «как до правки» на том же коде;
- `--warmup-prewarmed`-сценарий эмулируется так же, как в `loading_screen.gd`:
  `get_tree().set_meta("battle_prewarmed", true)` перед инстанцированием Main.

Команды (движковые аргументы — до `--`):

```
godot_console --path . tools/FirstClashProbe.tscn -- --warm --quality=high --novsync --tag=final-warm-desktop-high
godot_console --path . --rendering-method gl_compatibility tools/FirstClashProbe.tscn -- --warm --mobile --layout=844x390 --quality=low --novsync --tag=ab-after-mobile-compat-low
godot_console --path . --rendering-method gl_compatibility tools/FirstClashProbe.tscn -- --warm --skip-clash-warm --tag=ab-before-compat-high --quality=high --novsync
godot_console --path . --rendering-method gl_compatibility tools/FirstClashProbe.tscn -- --warm --action=number --tag=final-number-compat --quality=high --novsync
```

Сырые данные: `docs/qa-first-clash/first_clash_*.json` (+ скриншоты `.png`).
Консольные логи одного прогона до и после — `docs/qa-first-clash/run-*.log`.
`ab-before-*` — тот же код с отменённым прогревом (чистый A/B), `final-*` /
`ab-after-*` — после правки.

Стенд: Windows, Xeon E5-2680 v4, AMD RX 570, Godot 4.7.2, Forward+ и
`--rendering-method gl_compatibility`. Это **не телефон**: мобильные прогоны
задают `mobile_ui`, 844×390 и `quality=low`, но исполняются на десктопном GPU.

---

## 3. Что именно не прогревал WarmupFlow

Проверено по кадрам (причина всегда `render`, `process` < 3 мс):

1. **VFX удара.** `WarmupFlow` → `vfx_preloader.gd` рисует 10 сцен в своём
   `SubViewport(own_world_3d = true)`. В реальном мире первый `vfx_hit_01`
   всё равно компилировался: 11+ мс на создание сцены (`_acquire_vfx`) и
   ~44–60 мс на первый draw. `spawn_vfx` дополнительно включает emission и
   `Light3D` — это отдельные варианты материала/света.
2. **Damage number.** `vfx_preloader` греет `Label3D` с `font_size = 64`,
   `outline_size = 8`, **без `no_depth_test`**. Реальные числа
   (`game.gd:_acquire_number_label`) — `no_depth_test = true`,
   `outline_size = 12`, размеры **64 / 76 (крит) / 56 (хил)**. Первый draw:
   до 78.8 мс render.
3. **Пулы боевых эффектов.** `_prepare_effect_pools()` создаёт
   `burst_pool` (CPUParticles3D), `ring_pool` (soft_ground_glow),
   `root_spike_pool`, `shell_beam_pool`, `projectile_pool`, но все они
   `visible = false` — значит **никогда не рисовались** до первого умения/смерти.
   Первый ульт: 61–335 мс.
4. **Материалы, создаваемые на каст.** `lightning_strike_fx()` (CylinderMesh +
   unshaded additive + `no_depth_test`) и `earthquake_fx()` (ArrayMesh +
   unshaded alpha + `cull_disabled`) строятся заново каждый каст — их pipeline
   тоже не был прогрет.
5. **Kill feed.** `hud.gd:_team_icon()` лениво делает `load("dark_team.png")`
   и строит `ImageTexture` крест при первом убийстве. Теперь иконки
   кэшируются заранее (HUD не редактировался, вызваны существующие методы).

Что проверили и **не** нашли заметной стоимости: синхронные `load()` в пути
удара/VFX (всё на `preload`), `duplicate()` материалов в момент удара (копии
готовятся заранее), `queue_free`, GC (в GDScript refcount, пауз нет), звук
(стримы предзагружены, первый звук не дал кадра > 16 мс), шрифты HUD
(панель выбора уже отрисовала их до боя).

---

## 4. Что изменено

`scripts/game.gd`:

| Строки | Что |
|---|---|
| 48–62 | `FIRST_CLASH_WARM_VFX` — 6 сцен удара, которые реально использует бой |
| 128–134 | флаги `_clash_warm_running/_clash_warm_done/first_clash_warm_ms` |
| 295 | `_start_first_clash_warm()` в `_ready` для не-туториала (все платформы, в т.ч. после WarmupFlow) |
| 414–418 | `_start_first_clash_warm()` — один раз, `call_deferred` |
| 421–618 | `_warm_first_clash_world()`: реальный World3D (`own_world_3d = false`), камера на `y = -100`; 2 кадра на каждый VFX с emission/светом/частицами; Label3D 64/76/56 ровно как `damage_number`/`heal_number`; «СТАН» + torus; показ и скрытие реальных пулов; `lightning_strike_fx` и `earthquake_fx` off-screen; прогрев иконок kill feed |
| 1897–1905 | `start_match` ждёт прогрев **после спавна героев**, до `state = "live"` (панель выбора ещё на экране) |

Гарантии безопасности:

- прогрев не спавнит `HeroUnit`, не трогает HP/урон/КД/позиции героев;
- все прогревочные ноды стоят на `y = -100`, вне камеры матча, и удаляются;
- у пулов только временно включается `visible/emitting`, затем возвращается
  исходное состояние; `busy` не выставляется;
- `earthquake_timer/intensity` сбрасываются после прогрева;
- при `tutorial_mode` новый прогрев не запускается (у обучения свой
  `_warm_tutorial_assets`, его не меняли);
- если прогрев почему-то не завершился, `start_match` ждёт не более 10 с.

`tools/first_clash_probe.gd` + `.tscn` — новый QA-пробник, в игру не входит
(`tools/*` исключены из экспорта).

---

## 5. Проверки

| Проверка | Результат |
|---|---|
| `tools/FirstClashProbe.tscn`, 20+ прогонов (до/после, 7 конфигураций) | все дошли до конца, JSON + PNG записаны |
| A/B на одном коде: `--warm --skip-clash-warm` vs `--warm` | Compatibility: 62.7 → 13.2–18.8 мс; mobile+Compatibility: 70.8 → 6.6–7.5 мс; кадров > 33 мс нет |
| Кадры > 16 / 33 / 50 мс в окне стычки после правки | Forward+ desktop: 0 / 0 / 0; Compatibility desktop: 0–1 (>16.7, максимум 18.8) / **0** / **0** |
| `tools/HpDesyncProbe.tscn` | `HP_DESYNC_CHECKS=93 FAILURES=0` (прогрев не ломает спавн/HP/бары) |
| `godot_console --headless --path . --check-only --script res://scripts/game.gd` | без parse error (только ожидаемый `Identifier not found: NetworkManager` в offline-проверке) |
| `--headless --path . --quit` | запускается, новых `SCRIPT ERROR` от `game.gd`/пробника нет |

Скриншоты подтверждают, что снят реальный бой (HUD, damage number, VFX, боты):
`docs/qa-first-clash/*.png`.

---

## 6. Что осталось / риски

1. **Стартовый кадр матча** (не стычка) всё ещё 17–31 мс: это `start_match`
   спавнит 6 героев (загрузка моделей/анимаций + HUD) в одном кадре. Прогрев
   его не убирает; если это тоже раздражает — отдельная задача на асинхронный
   спавн/`_warm_class_models` в реальном мире.
2. **WarmupFlow** сам по себе по-прежнему не покрывает перечисленные пункты
   раздела 3. Правка в `game.gd` делает это за него; агенту по прогреву
   `warmup_flow.gd` можно не дублировать VFX/Label3D, но полезно знать, что
   его скрытый viewport с `own_world_3d = true` на Compatibility не создаёт
   pipeline боевого мира. Во время работы другой агент как раз правил
   `warmup_flow.gd` (в середине был короткий parse error); пробник в таком случае
   печатает `FIRST_CLASH_WARMUP_UNAVAILABLE` и продолжает без WarmupFlow.
3. **Стоимость прогрева** 0.55–0.92 с за панелью выбора. Если игрок нажмёт
   «Play» мгновенно, `start_match → live` вырастет на остаток прогрева
   (до ~0.4 с), но без фриза в бою.
4. **Мобильный веб на реальном телефоне не проверен** — только эмуляция
   профиля на десктопном GPU. Абсолютные мс на телефоне будут выше; вывод
   «render-pipeline, а не CPU» переносится, потому что после прогрева кадр
   падает до единиц мс при том же CPU.
5. **Пер-каст аллокации** `earthquake_fx` (SurfaceTool + материал) остались:
   после прогрева это ~2–3 мс CPU на ульт, не фриз. Кэшировать материал между
   кастами — отдельная правка, меняет код умения.
6. Прогрев выполняется на **каждой** загрузке `Main.tscn` (каждый матч), а не
   только в первом. Это осознанно: навигация/камера/свет в новом инстансе
   могут отличаться; цена скрыта панелью.
