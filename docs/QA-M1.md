# M1 QA — платформенное ядро (24.11.2026)

Ветка `mobile-ui`, база — `0646e7d`. Прод не деплоился: `main` `9272be6`,
PCK `48 925 168`, `/health` не трогали.

## Что проверялось

- Autoload `Platform` и выбор адаптера по feature tags.
- Standalone: реклама/оплата недоступны, mock-начислений нет.
- VK-сборка: VK Bridge только в ней, покупки/реклама пока недоступны.
- Сцены `Lobby`, `Main`, `ResultsScreen`.
- Серверные тесты.
- Размеры PCK/HTML и фактическая загрузка в браузере.

## Результаты

| Проверка | Результат |
|---|---|
| `godot_console --headless --path . --quit` | exit 0, `[Platform] id=standalone`, без `SCRIPT ERROR` |
| `res://scenes/Main.tscn` | exit 0, сцена грузится |
| `res://scenes/ResultsScreen.tscn` | exit 0, сцена грузится |
| `res://tools/PlatformProbe.tscn` | 22/22 PASS, `PLATFORM_PROBE_FAILURES=0` |
| `go test -count=1 ./...` | ok, 5.2 s |
| Standalone web | PCK `48 934 704`, HTML `10 962`, `vk-bridge.min.js` нет |
| VK web | PCK `48 934 688`, HTML `11 123`, `vk-bridge.min.js` есть |
| Standalone в браузере | `[Platform] id=standalone adapter=Standalone`, PCK 200, `SCRIPT ERROR` нет |
| VK в браузере | `[Platform] id=vk adapter=VK`, PCK 200, bridge 200, `SCRIPT ERROR` нет |

Сборки: `python tools/web_export.py --platform standalone|vk`.
Standalone лежит в `build/web` (`index_20261124_102851.pck`), VK — в
`build/web-vk` (`index_20261124_102909.pck`).

## Что именно доказано

- `Platform.purchase()` и `Platform.show_rewarded_ad()` в standalone возвращают
  неуспех; `AdManager` не эмитит `rewarded_ad_completed` без реального адаптера.
- В магазине standalone нет кнопки «Купить осколки»; в панели пополнения нет
  слайдера и кнопки оплаты, только «Пополнение недоступно в этой версии игры».
- В результатах боя кнопка «Получить x2 за рекламу» скрыта без rewarded-адаптера.
- В standalone HTML/PCK нет VK Bridge; в VK-сборке он есть и `Platform` выбирает
  `VKAdapter` по feature tag.
- Геймплей, баланс, боты, экономика и JSON тюнинга оружия не менялись.

## Кадры

- `docs/qa-m1-shop-standalone.png` — магазин без «Купить осколки».
- `docs/qa-m1-topup-standalone.png` — панель пополнения с честным «недоступно».

Сняты на десктопе 1280×720 (`tools/PlatformUiProbe.tscn`). На телефоне после
M1 не перепроверялись.

## Ограничения

- VK-сборка проверена локально, не в реальном VK; авторизация/`sign` — M2.
- Реальные VK Ads/Голоса и OKи не подключены; покупки честно недоступны до M4/M5.
- В PCK пока входят все адаптеры-заглушки; нарезка по платформам — позже.
- Прод не обновлялся; это локальные сборки.
