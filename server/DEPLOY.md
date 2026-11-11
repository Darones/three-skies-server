# RelaxDev deployment

## Project settings

- Repository: `Darones/three-skies-server`
- Branch: `main`
- Root directory / Build context: `server`
- Build type: **Docker**
- Dockerfile: `Dockerfile` (relative to the project root `server`)
- Container port: `8080`

Local Docker build check:

```bash
docker build -t three-skies-server ./server
```

If the platform uses Go auto-detection instead of Docker, set the project root to
`server` as well. The Go server reads the port from `PORT` and listens on all
interfaces.

## Environment variables

Add in **Project → Variables**:

```text
DATABASE_URL=postgres://USER:PASSWORD@HOST:5432/DB?sslmode=require
```

`PORT=8080` is supplied by RelaxDev automatically; the server also defaults to
8080 when `PORT` is empty.

Do not put the database password into the repository or Dockerfile.

## PostgreSQL

1. Open **Project → Databases → PostgreSQL** and create a database.
2. Attach it to the project; RelaxDev adds `DATABASE_URL` automatically.
3. Apply the schema in the database studio or with `psql`:

```bash
psql "$DATABASE_URL" -f schema.sql
```

The server also creates the `players` and `matches` tables at startup, so a
fresh database works without a manual migration. `schema.sql` is kept for
deployments where migrations are applied separately.

## Domain and WebSocket

Attach the domain `three-skies-server.relaxdev.ru` to the service and route it to the
container port `8080`. The same HTTP listener serves REST and the WebSocket
endpoint at `/ws`; RelaxDev's proxy must allow WebSocket upgrades.

Client defaults:

- REST: `https://three-skies-server.relaxdev.ru`
- WebSocket: `wss://three-skies-server.relaxdev.ru/ws`

## Auto-deploy

RelaxDev supports GitHub push auto-deploy through its own repository webhook.
Enable **Auto-deploy** in the project after connecting the GitHub repository.
A GitHub Actions deploy workflow is not required.

## Local testing

Override the production endpoints without editing the project:

```powershell
$env:THREE_SKIES_API_BASE_URL = "http://127.0.0.1:8080"
$env:THREE_SKIES_WS_URL = "ws://127.0.0.1:8080/ws"
```

The same values can be changed in `project.godot` under `[network]`.
