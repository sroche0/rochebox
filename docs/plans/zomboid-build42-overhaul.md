# Plan: Project Zomboid server overhaul (mod management, Build 42.20, Dockerfile/compose cleanup)

Status: in-progress
Date: 2026-07-27

## Problem

The `project_zomboid` server config was restructured for the original Build 42 unstable pin
(commit `ccd3a51`, "Updating zomboid server for build 42 (#9)") — files got split into
`configs/` and `scripts/`, and the server moved from a prebuilt third-party image
(`renegademaster/zomboid-dedicated-server`) to a locally-built image using `steamcmd`. That
restructure left several things broken or inconsistent, and now Build 42.20 is landing on
Steam's **stable/default** branch on 2026-07-29, which requires its own set of changes on top.

Specifically, as currently observed in the repo:

- `game_servers/project_zomboid/scripts/mod_manager.py` (`generate_strings()`) still writes to
  `project_zomboid/PigeonGrindhouse.ini` and `docker-compose.yaml` — neither path exists anymore.
  The INI moved to `project_zomboid/configs/PigeonGrindhouse.ini`, and there is no
  `docker-compose.yaml` at all (mods are set via `MOD_NAMES`/`MOD_WORKSHOP_IDS` in
  `project_zomboid/override.env`, loaded by `game_servers/compose.project_zomboid.yml`).
- `game_servers/project_zomboid/scripts/get_changes.sh` hardcodes an unrelated path
  (`/home/shawn/git/game_configs`) and calls raw `docker stop` / `docker-compose up`, bypassing
  `crabbot` and the current repo layout entirely.
- `game_servers/project_zomboid/Dockerfile` hardcodes `SERVER_BRANCH=""` twice in its `ENV`
  block (lines 22 and 25), which clobbers the `ARG SERVER_BRANCH` value passed in from
  `compose.project_zomboid.yml`'s `build.args`. The `-beta ${SERVER_BRANCH}` flag `entry.sh`
  passes to `steamcmd` is therefore always empty — the `42.13.1` pin in the compose file is
  currently a no-op.
- The same Dockerfile's `COPY scripts/entry.sh` and `COPY scripts/install.scmd` don't match
  reality: both files live directly in `project_zomboid/`, not `project_zomboid/scripts/`. Build
  context is `project_zomboid` (per compose), so `docker build` should fail outright on these
  COPY steps as written.
- `compose.project_zomboid.yml` still sets `GAME_VERSION=public`, `PAUSE_ON_EMPTY=true`,
  `PUBLIC_SERVER=true`, `USE_STEAM=true` as plain `environment:` entries — these were options for
  the old `renegademaster` image's entrypoint contract and are not read anywhere by the current
  `entry.sh`.
- Port mappings are inconsistent between the Dockerfile's `EXPOSE` (`27015/tcp`, `27015/udp`,
  `27020/udp`, `16261/tcp`, `16262/udp`) and the compose file's published `ports:`
  (`8766/udp`, `16261/udp`, `16262/udp`, `27015/tcp`) — `16261/tcp`, `27015/udp`, and `27020/udp`
  are exposed but never published, while `8766/udp` is published but never exposed.
- `install.scmd` (a steamcmd script file) is copied into the image but never invoked —
  `entry.sh` calls `steamcmd.sh` directly with inline arguments instead.

## Goal

- Mod management scripts (`mod_manager.py`, `mod_list.csv`, `get_changes.sh`) work correctly
  against the current `configs/`/`scripts/` layout, driven through `crabbot`.
- The server runs Build 42.20 pulled from Steam's default/stable branch, with the `SERVER_BRANCH`
  plumbing actually functional (or intentionally removed if no longer needed).
- `docker build` succeeds cleanly for the `project_zomboid` image, and `docker compose up` on
  `crabbot project_zomboid up` (or manually with `docker compose -f
  compose.project_zomboid.yml up -d`) produces a functioning Build 42.20 server, tested with a
  Steam client connecting to it.
- Dockerfile/compose are internally consistent (no dead env vars, no EXPOSE/publish mismatches,
  no unused/dead files) and reasonably sized/cached.

## Non-goals

- Migrating existing Build 41 world saves to Build 42 (per Indie Stone, saves are not
  compatible — this is a fresh-world / opt-in move, not a migration).
- Changing the mod list content itself (`mod_list.csv` entries) — only the tooling that consumes
  it.
- Reworking `matrix/` or any other game server in `game_servers/` — Zomboid only.
- Wiring up `install.scmd` unless phase 3 investigation concludes it's worth doing instead of
  deleting it.

## Approach

### Phase 1 — Mod management bug fixes for the current project layout

- [x] Fix `mod_manager.py`'s `generate_strings()` to write to
      `project_zomboid/configs/PigeonGrindhouse.ini` instead of the stale
      `project_zomboid/PigeonGrindhouse.ini` path.
- [x] `generate_strings()` now writes `MOD_NAMES=`/`MOD_WORKSHOP_IDS=` directly into
      `project_zomboid/override.env` in place of the nonexistent `docker-compose.yaml` write,
      matching how the compose file actually consumes mods today.
- [x] Found and fixed a second, independent bug while verifying the above: the INI regexes
      (`Mods=.+`, `WorkshopItems=.+`) required at least one character after `=`, so they silently
      skipped the real (empty-by-default) `Mods=`/`WorkshopItems=` lines and instead corrupted a
      comment further down the file that happens to contain example text
      (`... Example: WorkshopItems=514427485;513111049`). Anchored both the INI and `override.env`
      regexes to line start/end with `re.MULTILINE` and switched to `.*` so empty fields match.
- [x] Fixed `read_mods_from_file()`'s default INI path to `configs/PigeonGrindhouse.ini`, and
      `read_mods_from_disk()`'s hardcoded `/opt/zomboid/ZomboidDedicatedServer` path (a stale
      bare-metal path) to the `APPDATA`-based `server-files` volume path used by
      `compose.project_zomboid.yml`.
- [x] Rewrote `get_changes.sh`: no more hardcoded `/home/shawn/git/game_configs` path (finds the
      repo root via `git rev-parse --show-toplevel` instead), and it now drives updates through
      `crabbot project_zomboid update` instead of raw `docker`/`docker-compose` calls. Kept the
      script rather than deleting it — open question below if it should go away entirely.
- [x] Verified end-to-end against scratch copies of `mod_list.csv`, `configs/PigeonGrindhouse.ini`,
      and a synthetic `override.env` (the real `override.env` is `600`/not readable by this
      account): ran the fixed `mod_manager.py -gen` and confirmed the real `Mods=`/`WorkshopItems=`
      INI lines and `override.env`'s `MOD_NAMES=`/`MOD_WORKSHOP_IDS=` lines update correctly, with
      the misleading comment and other unrelated lines left untouched.

### Phase 2 — Bump to Build 42.20

- [ ] Fix the Dockerfile `ENV` block so `SERVER_BRANCH` actually inherits `ARG SERVER_BRANCH`
      (e.g. `ENV SERVER_BRANCH=${SERVER_BRANCH}`) instead of being hardcoded to `""` twice.
- [ ] Fix the `COPY scripts/entry.sh` / `COPY scripts/install.scmd` paths in the Dockerfile to
      match where those files actually live (`project_zomboid/entry.sh`,
      `project_zomboid/install.scmd`, i.e. drop the `scripts/` prefix — or move the files into
      `scripts/` instead, whichever keeps the layout more consistent with `configs/`).
- [ ] Confirm whether Build 42.20 should be pulled via an explicit `-beta` branch name or the
      default/public branch now that 42.20 is stable (per Indie Stone's 2026-07-29 announcement,
      default/public becomes Build 42 at that point; `-beta 42.19` and `-beta legacy41` are the
      opt-out branches). Update `compose.project_zomboid.yml`'s `build.args.SERVER_BRANCH` and
      `image:` tag accordingly (currently pinned to `42.13.1`).
- [ ] Re-check resource sizing: Build 42 is documented as heavier on RAM/CPU than Build 41.
      Review `MAX_RAM` (currently `4096m` in `sample.override.env`) and the Dockerfile's
      `MEMORY_XMX_GB=8`/`MEMORY_XMS_GB` against actual host capacity.
- [ ] `docker build` the image locally and confirm it completes without error (validates the
      Phase 2 Dockerfile fixes above).
- [ ] Bring the server up via `crabbot project_zomboid up`, confirm `steamcmd` pulls the expected
      branch/version (check logs for the actual installed build number), and connect with a Steam
      client to confirm the world loads and Build 42.20 features are present.
- [ ] Update `configs/PigeonGrindhouse_SandboxVars.lua` / `PigeonGrindhouse.ini` if 42.20's
      changelog introduces new or renamed sandbox/server options not present in the current
      configs (carried over from the 42.13-era config in `ccd3a51`).
- [ ] Confirm the `HEALTHCHECK`'s `pgrep "ProjectZomboid"` still matches the running process name
      under 42.20.

### Phase 3 — Dockerfile / compose optimization pass

- [ ] Remove dead `environment:` entries in `compose.project_zomboid.yml` left over from the old
      `renegademaster` image contract (`GAME_VERSION`, `PAUSE_ON_EMPTY`, `PUBLIC_SERVER`,
      `USE_STEAM`) that `entry.sh` never reads — or wire them up in `entry.sh` if any are still
      wanted behaviors, but don't leave them as silent no-ops either way.
- [ ] Reconcile the Dockerfile's `EXPOSE` list against `compose.project_zomboid.yml`'s `ports:`
      and Project Zomboid's actual required ports; drop or add entries so the two agree and
      nothing unused is published.
- [ ] Decide the fate of `install.scmd`: either wire it into `entry.sh` (replacing the inline
      `steamcmd.sh` invocation) or delete it as dead weight.
- [ ] Remove the commented-out `# entrypoint: ["tail", "-f", "/dev/null"]` debug line and the
      commented `${CONFIGS}/project_zomboid` volume mount in `compose.project_zomboid.yml` if
      they're no longer needed, or document why they're kept.
- [ ] Review Dockerfile layering/caching (e.g. whether `steamcmd` install steps could be baked
      into the image at build time vs. `entry.sh` re-running `app_update` on every container
      start) for faster restarts.
- [ ] Add resource limits (`deploy.resources` or `mem_limit`) to `compose.project_zomboid.yml`
      consistent with whatever RAM sizing was settled on in Phase 2.
- [ ] Re-verify `ADMIN_USERNAME`/`ADMIN_PASSWORD` defaults (`admin`/`admin` in the Dockerfile)
      are always overridden by `override.env` in practice, and aren't accidentally shippable
      as-is.

## Open questions

- Should `mod_manager.py -gen` target `override.env` directly, or should mod list generation
  stay a manual copy/paste step into `override.env` from a generated reference file? (Phase 1,
  resolved during implementation.)
- Does Indie Stone's 42.20 stable release actually require a `-beta` branch name at all, or does
  dropping `-beta` entirely pull the correct default/public branch? Needs confirming against the
  live steamcmd branch list closer to/after 2026-07-29. (Phase 2.)
- Is `get_changes.sh` still wanted at all now that `crabbot` exists, or should it just be
  deleted? (Phase 1.)
- What's the actual host RAM budget available for bumping `MAX_RAM`/`MEMORY_XMX_GB`? (Phase 2.)

## Risks / rollback

- Build 42 saves are incompatible with Build 41 — bringing the server up on 42.20 effectively
  starts a fresh world. Confirm with the group before Phase 2 goes live on the real server, and
  back up the existing `${APPDATA}/zomboid/server-files` and `${APPDATA}/zomboid/config`
  directories first regardless.
- The Dockerfile fixes in Phase 2 (COPY paths, `SERVER_BRANCH` passthrough) are prerequisites for
  the image to build at all — if Phase 2 is rushed without them, `docker build`/`crabbot
  project_zomboid update` will fail outright.
- Rollback for Phase 2: keep the previous working `image:` tag (`42.13.1`, once actually fixed to
  build) available/pullable so `compose.project_zomboid.yml` can be reverted to it if 42.20 has
  launch-week issues; Indie Stone's own `legacy41`/`42.19` branches provide a further fallback if
  needed.
