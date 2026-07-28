# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository overview

`rochebox` is a self-hosted homelab config repo, not an application. It has two independent parts
that don't share code or a build system:

- `game_servers/` — Dockerized dedicated game servers, managed by a CLI tool called `crabbot`.
- `matrix/` — Docker Compose stack for a Matrix homeserver (Synapse) plus bridges (WhatsApp;
  Discord/Google Chat are present in `docker-compose.yml` but commented out).

There is no top-level build, lint, or test tooling — each subdirectory is operated independently
via Docker Compose or the `crabbot` script described below.

## game_servers/ — crabbot

`crabbot` (`game_servers/crabbot`) is a small Python 3.13 CLI that wraps `docker compose` for
each game server. It auto-discovers servers by scanning its own directory for
`compose.<server>.yml` files, so adding a new server means adding a new `compose.<name>.yml` at
the `game_servers/` root — no registration needed elsewhere.

```
crabbot <server_name> <up|down|pull|update|ps|restart>
```

- `update` = pull, pre-down hook, down, pre-up hook, up.
- `restart` runs `docker restart` directly and skips pre-up/pre-down hooks.
- Current servers: `core-keeper`, `factorio`, `foundry`, `minecraft`, `project_zomboid`,
  `satisfactory`, `teamspeak`, `valheim`, `vrising`.

Install/uninstall (`game_servers/bin/install.sh`, `uninstall.sh`):
- Install stages env files (see below), then symlinks `crabbot` into `~/.local/bin` and adds it
  to `PATH`.
- Uninstall removes the symlinks only; it does **not** touch `APPDATA` or local env file edits.

### Env file convention

Each server directory has a `sample.override.env` (tracked in git) that `install.sh` copies to
`override.env` (gitignored, machine-local) on first install, if `override.env` doesn't already
exist. Likewise `game_servers/sample.env` is copied to `game_servers/.env` with `PUID`/`PGID`/`TZ`
filled in for the current user. Each `compose.<server>.yml` loads both `./.env` and
`./<server>/override.env` via `env_file`. When adding a new server or changing defaults, edit the
`sample.*` files (tracked); never expect `.env`/`override.env` themselves to be committed.

### Python tooling

`game_servers/` has its own `pyproject.toml`/`uv.lock` (Python >=3.13, managed with `uv`, no
runtime dependencies declared) covering `crabbot` and the one-off scripts under
`project_zomboid/scripts/` (`mod_manager.py`, `map_editor.py`) used for managing PZ mods and
trimming map/chunk save files. These are standalone scripts run directly with `python3`, not a
packaged library.

## matrix/

Plain Docker Compose stack (`matrix/docker-compose.yml`, no wrapper CLI): Synapse, a Postgres
backend (custom `postgres.Dockerfile`), synapse-admin, and mautrix bridges (each bridge gets its
own Postgres container/env file, e.g. `matrix/whatsapp-bridge-db.env`). Sample env templates live
under `matrix/sample/` (`.env.sample`, `postgres.env.sample`, `synapse.env.sample`) — copy these
to the real (gitignored) env files rather than editing them in place. Bring the stack up/down with
plain `docker compose` from `matrix/`.

## Working conventions

- All real secrets/config live in `*.env` files, which are gitignored; only `sample.env` and
  `sample.override.env`/`*.env.sample` templates are tracked. When changing a server's
  configurable settings, update the sample template, not a live env file.
- Server-specific persistent data (saves, binaries) lives outside the repo under `APPDATA`
  (`~/Games/crabbot` by default), not in the repo tree.
