# Baseline перед деплоем — 2026-11-27

- Прод: `https://three-skies-server.relaxdev.ru`
- Снято: 2026-11-27 16:41 MSK (13:41 UTC), только чтение, ничего не менялось
- Команды: `curl.exe` (Windows, без Accept-Encoding по умолчанию), SHA256 через `Get-FileHash`

## Сводная таблица

| Параметр | Значение |
|---|---|
| `GET /health` → status | `200` |
| `health.status` | `ok` |
| `health.success` | `true` |
| `health.database` | `ok` |
| `health.database_host` | `db-team-cmu810mz10007p401in9zmhkz` |
| `health.live_matches` | `0` |
| `health.online_players` | `0` |
| `health.uptime_seconds` | `53646` (≈ 14 ч 54 мин) |
| `GET /health` Content-Length | `158` |
| `GET /health` Content-Type | `application/json; charset=utf-8` |
| `HEAD /game/` → status | `302 Found` |
| `HEAD /game/` Location | `/game/?v=20261126_224708` |
| `HEAD /game/` Content-Length | не отдаётся (только у GET-редиректа: `47`) |
| `HEAD /game/` Cache-Control | `no-store` |
| `GET /game/` → status | `302` → follow → `200 OK` |
| `GET /game/?v=...` Content-Length | **нет** (`Transfer-Encoding: chunked`), реально скачано `14740` байт |
| `GET /game/?v=...` ETag | `"149c-18ebb9d935dd1e00"` |
| `GET /game/?v=...` Cache-Control | `no-cache` |
| `GET /game/?v=...` Last-Modified | `Thu, 26 Nov 2026 22:46:59 GMT` |
| `GET /game/?v=...` Vary | `Accept-Encoding` |
| `GET /game/?v=...` X-Content-Type-Options | `nosniff` |
| `HEAD /game/index.pck` → status | `200 OK` |
| `GET /game/index.pck` Content-Length / реально | `27859676` байт (26.57 MiB) |
| `index.pck` ETag | `"1a91adc-18ebb9dbfa63bcca"` |
| `index.pck` Cache-Control | `no-cache` |
| `index.pck` Last-Modified | `Thu, 26 Nov 2026 22:47:10 GMT` |
| `index.pck` Accept-Ranges | `bytes` |
| `index.pck` Content-Type | `application/octet-stream` |
| **SHA256 `/game/index.pck`** | **`2F74DE448B60A3DAC948271CA696F86CB58ABDF27C83DB7D06C5264BE5015B11`** |
| `GET /privacy` → status | `200` (6328 байт) |
| `GET /terms` → status | `200` (6681 байт) |
| `GET /admin/moderation` без токена | `403` ✅ (как ожидалось) |
| `HEAD /admin/moderation` без токена | `405` (роут только на GET) |
| `HEAD /game-vk/` → status | `302 Found` |
| `HEAD /game-vk/` Location | `/game-vk/?v=20261126_224708` |
| `HEAD /game-vk/?v=...` → status | `200 OK` |
| `HEAD /game-vk/?v=...` Content-Length | `1017` |
| `HEAD /game-vk/?v=...` ETag | `"3f9-18ebb9ce800cd200"` |
| `HEAD /game-vk/?v=...` Cache-Control | `no-cache` |
| `HEAD /game-vk/?v=...` Last-Modified | `Thu, 26 Nov 2026 22:46:13 GMT` |
| `HEAD /game-ok/` → status | `200 OK` (без редиректа) |
| `HEAD /game-ok/` Content-Length | `1016` |
| `HEAD /game-ok/` ETag | `"3f8-18ebb9ce800cd200"` |
| `HEAD /game-ok/` Cache-Control | `no-cache` |
| `HEAD /game-ok/` Last-Modified | `Thu, 26 Nov 2026 22:46:13 GMT` |
| Сборка на проде (версия в редиректе) | `20261126_224708` |
| Репо `three-skies-ads-deploy` HEAD | `ab67eb2 build: smooth warmup, first-clash prewarm, desync and VK diagnostics` |
| Репо ветка | `deploy-ads` |
| Репо коммит (полный) | `ab67eb213807c08df13b6803788efd4c83fff575`, 2026-11-27 01:45:42 +0300 |
| `git status --porcelain` | 4 изменённых файла (незакоммичено, см. ниже) |

## Сырые данные

### `GET /health`

```json
{"database":"ok","database_host":"db-team-cmu810mz10007p401in9zmhkz","live_matches":0,"online_players":0,"status":"ok","success":true,"uptime_seconds":53646}
```

Заголовки: `content-length: 158`, `content-type: application/json; charset=utf-8`, `x-robots-tag: noindex, follow`.

### `HEAD /game/`

```
HTTP/1.1 302 Found
Cache-Control: no-store
Content-Type: text/html; charset=utf-8
Location: /game/?v=20261126_224708
X-Robots-Tag: noindex, follow
```

### `GET /game/?v=20261126_224708` (после follow)

```
HTTP/1.1 200 OK
Accept-Ranges: bytes
Cache-Control: no-cache
Content-Type: text/html; charset=utf-8
Etag: "149c-18ebb9d935dd1e00"
Last-Modified: Thu, 26 Nov 2026 22:46:59 GMT
Vary: Accept-Encoding
X-Content-Type-Options: nosniff
X-Robots-Tag: noindex, follow
Transfer-Encoding: chunked
```

### `HEAD /game/index.pck`

```
HTTP/1.1 200 OK
Accept-Ranges: bytes
Cache-Control: no-cache
Content-Length: 27859676
Content-Type: application/octet-stream
Etag: "1a91adc-18ebb9dbfa63bcca"
Last-Modified: Thu, 26 Nov 2026 22:47:10 GMT
X-Content-Type-Options: nosniff
X-Robots-Tag: noindex, follow
```

### `HEAD /game-vk/?v=20261126_224708`

```
HTTP/1.1 200 OK
Accept-Ranges: bytes
Cache-Control: no-cache
Content-Length: 1017
Content-Type: text/html; charset=utf-8
Etag: "3f9-18ebb9ce800cd200"
Last-Modified: Thu, 26 Nov 2026 22:46:13 GMT
X-Content-Type-Options: nosniff
X-Robots-Tag: noindex, follow
```

### `HEAD /game-ok/`

```
HTTP/1.1 200 OK
Accept-Ranges: bytes
Cache-Control: no-cache
Content-Length: 1016
Content-Type: text/html; charset=utf-8
Etag: "3f8-18ebb9ce800cd200"
Last-Modified: Thu, 26 Nov 2026 22:46:13 GMT
X-Content-Type-Options: nosniff
X-Robots-Tag: noindex, follow
```

### `git -C C:\myGames3D\three-skies-ads-deploy`

```
ab67eb2 build: smooth warmup, first-clash prewarm, desync and VK diagnostics
```

```
 M server/ws.go
 M server/ws_integration_test.go
 M server/ws_sync_probe_test.go
 M server/ws_test.go
```

## Артефакт baseline PCK

- Путь: `C:\Users\Professional\AppData\Local\Temp\opencode\pck-baseline\index.pck` (вне репозитория)
- Размер: `27 859 676` байт
- SHA256: `2F74DE448B60A3DAC948271CA696F86CB58ABDF27C83DB7D06C5264BE5015B11`
- HTTP: `200`, скачано ровно `Content-Length` (обрезки нет)

## Наблюдения (без правок)

1. `/game/` и `/game-vk/` отдают `302` на URL с версионным `?v=20261126_224708` — обычный антикеш, версия = метка сборки (`20261126_224708` = 26.11.2026 22:47:08 UTC).
2. `GET /game/?v=...` идёт **chunked без Content-Length** (14740 байт фактически). Если после деплоя понадобится сверять HTML — сравнивать размер тела, а не `Content-Length`.
3. ETag `"149c-..."` для `/game/` = 5276, что не совпадает с фактическими 14740 байтами. Похоже, ETag считается по файлу-шаблону, а отдаётся страница с инъекцией версии. Практический риск: `If-None-Match` может дать `304` при изменившейся инъекции. Наблюдение, не блокер.
4. `/game-ok/` отдаётся сразу `200`, а `/game-vk/` — через `302`. Разное поведение для двух VK/OK-входов стоит учесть в чек-листе после деплоя.
5. `HEAD /admin/moderation` = `405`, `GET` без токена = `403` —защита на месте.
6. В рабочем дереве `three-skies-ads-deploy` на ветке `deploy-ads` есть 4 незакоммиченных изменённых файла сервера (`ws.go` и 3 теста). Перед деплоем нужно понимать: собирается ли бинарь из этих незакоммиченных правок.
7. Аптайм 53646 с — процесс поднят ~14 ч 54 мин назад, то есть прошлый деплой был примерно 2026-11-27 01:47 MSK (совпадает с коммитом `ab67eb2` в 01:45:42).
