# innbo

a personal home-inventory app

<img src="logo.png" alt="hugg" width="100"/>

## Prerequisites

- Go 1.24.3
- Flutter 3.44.8
- Docker + Docker Compose

## Local dev

### Backend

```
cp .env.example .env
```
fill in required values, then
```
docker compose up -d --build
docker compose exec backend /server bootstrap-pairing
```

That prints a pairing code, valid 15 minutes.

### Client

```
cd client
flutter pub get
flutter run -d macos   # or an Android emulator/device — see `flutter devices`
```

In the pairing screen, use `http://<your-machine's-LAN-IP>:8080` (backend)
plus the printed pairing code — this works from desktop, an Android
emulator, and a physical device alike, so the same running backend can
pair all of them at once. Set `POWERSYNC_PUBLIC_URL` in `.env` to that
same LAN IP too (see `.env.example`).

See [docs/INSTALL-MACOS.md](docs/INSTALL-MACOS.md) if a built `.dmg` is
blocked by Gatekeeper.

## Formatting & linting

### Backend
 `gofmt -l .` / [golangci-lint](https://golangci-lint.run) (config
in `backend/.golangci.yml`)

### Client
`dart format .` / `flutter analyze`.

### Pre-commit hook

Checks the above on every commit (auto-fixes formatting, blocks on lint
errors); CI re-checks on every push regardless. Requires
[lefthook](https://github.com/evilmartians/lefthook) and
[golangci-lint](https://golangci-lint.run) installed locally:

```
brew install lefthook golangci-lint   # or see each tool's own install docs
lefthook install
```

## More

- [docs/home-inventory-app-plan.md](docs/home-inventory-app-plan.md) —
  architecture and design decisions
- [docs/adr/](docs/adr/) — why things are the way they are
- [CONTEXT.md](CONTEXT.md) — domain glossary
