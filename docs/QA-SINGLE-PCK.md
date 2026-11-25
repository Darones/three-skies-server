# QA: один PCK, runtime VK/OK/Standalone (25.11.2026)

> Обновление 25.11.2026, вечер: поверх этой сборки задеплоены `bfbfdba`
> (PCK **48 975 700**, обучение этапы 1–4) и `46b510d` (скрытие 12+ после
> старта). Схема одного PCK не менялась.

Ветка исходников `mobile-ui`. Деплой-коммит `56c5cc3` (origin/main).
Прод: `https://three-skies-server.relaxdev.ru/game/`.

## Что изменено

- `export_presets.cfg`: оставлен один web-preset **Web Standalone**. Прежние
  `Web VK` и `Web OK` удалены.
- `tools/web_export.py`: один экспорт `build/web` → один
  `server/web/index.pck`; генерирует тонкие redirect-shell'ы
  `server/web-vk/index.html` и `server/web-ok/index.html`.
- `tools/server_web.py` — совместимый враппер; `server_web_vk.py` и
  `server_web_ok.py` удалены, чтобы никто снова не собрал отдельные PCK.
- `scripts/platform/platform.gd`: выбор адаптера в runtime.
  - OK: `vk_client=ok`, `ok_client`, `platform=ok`, `local_access_token`,
    referrer `ok.ru`.
  - VK: `vk_user_id`, `vk_app_id`, `vk_ts`, `vk_platform` в query или hash.
  - Иначе Standalone. Feature tags оставлены только как совместимость.
- `scripts/platform/vk_adapter.gd`: URL-fallback launch params теперь читает
  и `window.location.hash` — VK часто кладёт подписанные параметры туда.
- OK-адаптер и VK-адаптер остаются в одном PCK; выбор — только runtime.
- OK-shell добавляет `vk_client=ok`; VK/OK shell сохраняют весь query и hash,
  поэтому `vk_user_id/sign/vk_ts` не теряются на редиректе.

## Проверки

| Проверка | Результат |
|---|---|
| `godot_console --headless --path . --quit` | exit 0, `[Platform] id=standalone` |
| `tools/PlatformProbe.tscn` | 22 PASS, 0 FAIL |
| `tools/OKUiProbe.tscn` | 10 PASS, 0 FAIL |
| `go vet ./...` | ok |
| `go test -count=1 ./...` | ok, 5.2 s |
| `python tools/web_export.py` | one PCK `48 971 828` |
| `server/web` PCK count | 1 (`server/web/index.pck`) |
| `server/web-vk` | только `index.html` (redirect shell) |
| `server/web-ok` | только `index.html` (redirect shell) |

### Браузер (локальный сервер над `server/web*`)

| URL | Ожидание | Лог |
|---|---|---|
| `/game/` | Standalone | `[Platform] id=standalone adapter=Standalone` |
| `/game-vk/?vk_client=ok` | OK через shell | `[Platform] id=ok adapter=OK` |
| `/game/?vk_user_id=1&vk_app_id=54906713&vk_ts=...&sign=...` | VK | `[Platform] id=vk adapter=VK` |
| `/game-vk/#vk_user_id=1&...&sign=...` | VK, hash сохранён | `[Platform] id=vk adapter=VK` |
| `/game-ok/` | OK, shell добавил `vk_client=ok` | `[Platform] id=ok adapter=OK` |

Редиректы подтверждены: `/game-vk/#...` → `/game/#...`, `/game-ok/` →
`/game/?vk_client=ok`. Ошибок `SCRIPT ERROR` нет; только известное
предупреждение Godot про screen-space AA в Compatibility.

## Прод-деплой 25.11.2026

- Деплой-коммит `56c5cc3`, `/health` ok, `live_matches=0`.
- `/game/index.pck` → **48 971 828** (единственный PCK).
- `/game-vk/index.html` → 1017 байт (shell), `/game-vk/index.pck` → **404**.
- `/game-ok/index.html` → 1016 байт (shell), `/game-ok/index.pck` → **404**.
- `/game/index.html` содержит VK Bridge, reset-скрипт и
  `"fileSizes":{"index.pck":48971828,...}`.
- В реальном VK-приложении `vk.ru/games/app54906713` iframe загружается с
  `/game/`; в консоли `[Platform] id=vk adapter=VK`, лобби открылось:
  профиль «Андрей Давлеев», Маг, **195 321** осколок. VK-прогресс на месте.
- В реальном OK-приложении `ok.ru/app/512005268801` iframe загружается;
  в консоли `[Platform] id=ok adapter=OK`, лобби открылось после
  стабилизации сервера: профиль OK, 0 осколков, уровень 1 (отдельный
  прогресс). Первая попытка во время рестарта дала «Сервер не ответил» —
  это был рестарт контейнера, не ошибка сборки.
- Предупреждение `No loader found for resource:
  res://assets/weapons/wizards_staff_low.glb` повторяется в лобби VK.
  Оно не связано с одним PCK: путь отфильтрован экспортом и раньше;
  модель подставляется фолбэком. Записать в риски, не менять без задачи.
- `POST /auth/ok` проверен напрямую: QA UID `999000112` → профиль создан,
  `/account/delete` удалил его (`success=true`, player 136).
- Кадры: `docs/qa-single-pck-vk.png` (VK-лобби, 195 321 осколок),
  `docs/qa-single-pck-ok.png` (OK-лобби, отдельный профиль).

## Ограничения

- Полный 10-минутный бой в VK/OK после перехода на один PCK не прогонялся;
  проверены вход, лобби, профиль и прогресс.
- В лобби повторяется предупреждение `No loader found for resource:
  res://assets/weapons/wizards_staff_low.glb`. Путь отфильтрован экспортом
  и раньше; это не следствие одного PCK. Модель подставляется фолбэком,
  но предупреждение стоит убрать отдельной задачей.
- VK/OK-панели по-прежнему указывают на `/game-vk/`; это работает через
  shell. Переводить их сразу на `/game/` не обязательно.

- Реальный вход в VK/OK после этого деплоя нужно проверить в самих
  приложениях: подпись VK и OK-профиль.
- iPhone/VK webview и полный матч не перепроверялись.
- Старый отдельный `/game-ok/` PCK удалён; OK-приложение по-прежнему
  открывает `/game-vk/`, который теперь ведёт на общий `/game/`.
