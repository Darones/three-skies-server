# Ники: 3D Label3D → 2D screen-space (27.11.2026)

Задача: убрать `Label3D` над головами, оставить HP-бар 3D (заливка зелёная),
боты — `БОТ XXXX` (имя из game/server), скрытие в кустах/тумане сохранить,
на `q=low` (scaling_3d_scale 0.5) текст не должен мылиться.

## Как сделано

`scripts/world_name_layer.gd` — один общий `CanvasLayer` (layer 0: выше 3D,
ниже HUD-слоя 1) и внутренний класс `NameTag extends Label`.

- `NameTag._process` каждый кадр берёт `anchor.global_position + world_offset`
  и переводит в экран через `Camera3D.unproject_position()`
  (`get_viewport().get_camera_3d()` — фолбэк, если камера не передана).
- Позиция: `Vector2(screen.x - size.x * 0.5, screen.y - size.y)` — низ
  текстового бокса ровно над точкой над головой (2.78 от ступней, чуть выше
  3D-бара на 2.55).
- `is_position_behind()` и выход за `get_viewport_rect()` — лейбл паркуется в
  `(-4000, -4000)`; `visible` при этом НЕ меняется, им управляет герой
  (кусты/туман/preview), поэтому старые проверки `name_label.visible` работают.
- Шрифт `Philosopher-Bold.ttf`, 20 px (19 на mobile), outline 4 + тень;
  `mouse_filter = IGNORE`. Канвасный текст не масштабируется
  `scaling_3d_scale`, поэтому при `q=low` остаётся резким.
- Слой создаётся лениво первым героем и живёт в `current_scene`; лейбл сам
  удаляется по `anchor.tree_exiting`.

`scripts/hero.gd`: `name_label: Label` вместо `Label3D`; `_name_tag_text()`
(`БОТ ` добавляется только если имя ещё не начинается с «БОТ»/«BOT» — готовое
имя приходит из `game._next_bot_callsign()`/сервера), `_refresh_name_text()`,
цвета `NAME_COLOR_SELF/ALLY/ENEMY`, `HEALTH_FILL_COLOR` (зелёная заливка для
всех), `_update_name_visibility()` больше не трогает видимость через 3D.

`scripts/remote_player.gd`: то же для гостей/сетевых ботов; при смерти
(`apply_network_death`) и респавне ник явно скрывается/показывается, т.к. он
больше не ребёнок узла.

## Проверки

| Проверка | Результат |
|---|---|
| `tools/NameTagProbe.tscn` (новый) | **72/72 PASS**, exit 0 |
| `tools/BushStealthProbe.tscn` | 32/32, FAILURES=0 |
| `tools/HpDesyncProbe.tscn` | 93/93, FAILURES=0 |
| `tools/LobbyD1Probe.tscn` | LOBBY_D1_FAILURES=0 |
| `tools/TutorialCombatProbe.tscn` | TUTORIAL_COMBAT_FAILURES=0 |
| `godot --headless --path . --quit-after 120` | 0 SCRIPT ERROR / Parse Error |
| Лобби (`tools/LobbyProbe.tscn`) | визуально: ников поверх лобби нет |

Скриншоты (`q=low`, `844x390` c `--mobile` и `1440x734`):
`name_tags_desktop_low_1440x734.png`, `name_tags_mobile_low_844x390.png`.

Что реально проверяет `NameTagProbe`:
- ни один ник не `Label3D`; все `Label` в общем слое, Philosopher, outline ≥ 3,
  размер ≥ 16;
- боты — `БОТ <номер>` без двойного префикса, люди (локальный игрок, гости) —
  без префикса; союзник зелёный, враг красный, свой — свой цвет;
- лейбл стоит ровно в `unproject_position(head)` (ошибка 0.00 px) и выше точки
  головы;
- `q=low` → `root.scaling_3d_scale == 0.5`, лейбл остаётся canvas-item с тем же
  размером шрифта;
- за камерой лейбл паркуется off-screen, `visible` не меняется;
- в кустах ник врага скрыт, на 1.9 м — появляется;
- заливка 3D HP-бара зелёная у всех (hero + remote).

## Риски / что осталось

- HP-бар остался 3D (по заданию) — при `q=low` он мягкий; бар двигается в
  `_physics_process`, поэтому у героя с выключенной физикой (манекен туториала)
  он может отставать (было и раньше).
- Видимость врага по-прежнему решается дистанцией до ближайшего союзника (12 м)
  и кустами; сквозь стену в пределах 12 м ник врага виден — это старое
  поведение `_update_name_visibility`, менять не стал (BushStealthProbe
  опирается на него).
- На 844x390 верхняя полоса HUD занимает ~20% экрана; ник врага у верхней
  кромки может оказаться под ней (слой 0 < HUD 1) или обрезаться у самого края.
  Это следствие камеры (45°, fov 46), а не лейбла.
- `Label3D` остались у AFK-метки и `HealthLabel` (пустой, скрыт) — вне задачи.
- `world_name_layer.gd` использует статическую ссылку на слой; при смене сцены
  слой умирает вместе с `current_scene` и пересоздаётся (проверено лобби →
  бой, `LobbyD1Probe` + `NameTagProbe`).
