# Plan: Project Zomboid server overhaul (mod management, Build 42.20, Dockerfile/compose cleanup)

Status: in-progress
Date: 2026-07-27 (updated 2026-07-29)

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

- ~~Mod management scripts (`mod_manager.py`, `mod_list.csv`, `get_changes.sh`) work correctly
  against the current `configs/`/`scripts/` layout, driven through `crabbot`~~ — superseded: Build
  42.20's built-in mod manager replaces this pipeline (see Phase 1). `get_changes.sh` stays as a
  plain git-pull-and-update convenience script.
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

**Superseded 2026-07-30**: Build 42.20 ships Indie Stone's own built-in mod manager, so this
whole CSV → INI/`override.env` pipeline is no longer the intended way to manage mods.
`scripts/mod_manager.py` and `mod_list.csv` are left in the repo as-is (not deleted — the curated
mod list in `mod_list.csv` may still be useful as a reference), but the automatic wiring is gone:
`get_changes.sh` no longer calls `mod_manager.py -gen`, so pulling repo changes and updating the
container is now just `git pull` + `crabbot project_zomboid update`, nothing mod-related. Also
worth noting for whoever picks this up: `MOD_NAMES`/`MOD_WORKSHOP_IDS` in `override.env` were
already dead before this — confirmed via grep that `entry.sh`, the `Dockerfile`, and compose never
read them; only `mod_manager.py` itself wrote/read them. Safe to delete those two lines from the
real `override.env` whenever convenient; they don't do anything either way now.

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

**Status: functionally complete, still uncommitted.** All checklist items below are done,
including the SandboxVars/INI vendor-diff work. `git status` shows 7 modified files —
`game_servers/compose.project_zomboid.yml`, `game_servers/project_zomboid/Dockerfile`,
`game_servers/project_zomboid/entry.sh`, `game_servers/project_zomboid/sample.override.env`,
`game_servers/project_zomboid/configs/PigeonGrindhouse.ini`,
`game_servers/project_zomboid/configs/PigeonGrindhouse_SandboxVars.lua`, and this plan doc.
Nothing has been committed yet. The only remaining blocker is Docker access for a real
`docker build` + `crabbot project_zomboid up` + Steam client bring-up (see below) — do that first
next session, then this phase can be considered done and ready to commit.

**2026-07-29 session note on Steam branch state:** queried `app_info_print 380870` anonymously
and found the `public` branch's buildid (`24449161`, updated ~07:21 EDT same day) already differs
from the `42.19` branch's buildid (`24438606`) — consistent with 42.20 shipping to default/public
on schedule today. However, the actual `app_update 380870` download (no `-beta`, i.e. tracking
`public`) that this session pulled for ground-truth came back with `buildid 24438606` in
`appmanifest_380870.acf` — matching `42.19`, not the `24449161` the branch API reported. This is
most likely CDN propagation lag (the branch pointer flips before all content servers have the new
depot chunks), not a mistake in the `-beta` flag. Net effect: this session's SandboxVars/INI
ground-truth diff is verified against whatever Steam actually served for `public` at download
time, which **may be 42.19-identical rather than true 42.20** content. Config schemas rarely
change within a single stable point release, so this is a low-risk gap, but if anything about the
sandbox/server options looks off after the real 42.20 client is out, re-run the vendor diff
(commands at the bottom of this section) and re-check.

This session downloaded the real Build 42.19 dedicated server files (steamcmd, app 380870,
anonymous login — free/no purchase needed) into a scratch dir to get ground truth instead of
guessing; that download does **not** persist in the repo or between sessions, so the findings
below are recorded here verbatim rather than left as "check the scratch files."

- [x] Fixed the Dockerfile `ENV` block so `SERVER_BRANCH` actually inherits `ARG SERVER_BRANCH`
      (`ENV ... SERVER_BRANCH=${SERVER_BRANCH} ...`) instead of being hardcoded to `""` twice.
- [x] Fixed `COPY scripts/entry.sh` / `COPY scripts/install.scmd` → `COPY entry.sh` /
      `COPY install.scmd` (dropped the `scripts/` prefix; left the files at `project_zomboid/`
      root rather than moving them into `scripts/`, since `scripts/` is host-side operator
      tooling and these are in-container build artifacts — different concerns).
- [x] Confirmed via a live, anonymous `steamcmd +app_info_print 380870` query (verified today,
      2026-07-27) that:
      - Steam's `public` branch is still Build 41 right now (`legacy41` has the identical
        buildid) — 42.20 genuinely hasn't shipped yet, confirming the 2026-07-29 date.
      - **There is no `42.13.1` branch anymore.** Indie Stone only keeps one rolling numbered
        checkpoint alive at a time (currently `42.19`, identical buildid to `unstable`), plus
        `legacy41` and `outdatedunstable`. Our old pin was already stale/broken independent of
        the ENV bug above.
      - Decision: track default/public (empty `SERVER_BRANCH`) rather than pin another numbered
        branch, since default/public becomes 42.20 on 2026-07-29 and that's a moving target we'd
        otherwise have to keep re-pinning by hand. Documented as a comment in the compose file.
        Known tradeoff: `entry.sh` re-runs `app_update` on every container start with no version
        freezing, so once this ships the server will also pick up future public hotfixes on every
        restart, not just the initial 42.20 jump — flagging this explicitly since it's a real
        behavior change, not hidden in a comment nobody reads.
- [x] Updated `compose.project_zomboid.yml`: `build.args.SERVER_BRANCH` → empty (tracks
      default/public), `image:` tag `42.13.1` → `42.20`.
- [x] **Found `MAX_RAM`/`MEMORY_XMX_GB`/`MEMORY_XMS_GB` were 100% dead config** — confirmed via
      the real downloaded server files that Zomboid's dedicated server only reads heap size from
      `-Xmx` inside `ProjectZomboid64.json`'s `vmArgs` (edited via `start-server.sh`'s own
      comment: "Edit memory option -Xmx in ProjectZomboid64.json"). `entry.sh` never touched that
      file, so these env vars never did anything, regardless of Build 41 vs 42. Shipped vendor
      default in 42.19 is `-Xmx8g`.
      - Fixed by adding a `sed` step in `entry.sh` that patches `-Xmx` in `ProjectZomboid64.json`
        from `MAX_RAM` *after* the `steamcmd validate` step (validate resets modified files to
        the manifest default, so the patch has to happen after, on every start — verified this
        ordering against the real downloaded `ProjectZomboid64.json`).
      - Removed the now-redundant `MEMORY_XMX_GB`/`MEMORY_XMS_GB` Dockerfile vars; `MAX_RAM` in
        `override.env` is the one real, functional knob.
      - Bumped `sample.override.env`'s `MAX_RAM` default from `4096m` to `8192m` — since this was
        previously a no-op, leaving it at 4096m while wiring it up for real would have silently
        *dropped* the vendor's already-adequate 8g default to 4g. 8192m matches vendor default as
        a safe floor; noted in-file that larger/more heavily modded deployments (our mod list is
        100+ mods) should go higher, per community guidance (6GB base + ~0.5GB/player, more for
        heavy mods).
      - Also fixed a second real bug found while testing this: `entry.sh` passed
        `-beta ${SERVER_BRANCH}` unquoted, so an empty `SERVER_BRANCH` (our new default/public
        case) collapsed to `-beta validate`, silently swallowing the `validate` integrity-check
        flag as if it were the branch name. Now builds the `-beta` flag conditionally via a bash
        array, only when `SERVER_BRANCH` is non-empty. Verified both branches (empty and
        `42.19`) produce the correct `app_update` command.
      - Added `exec` before the final `start-server.sh` launch in `entry.sh` so `docker stop`'s
        SIGTERM reaches the Java process directly instead of hanging on a non-exec'd bash PID 1 —
        small, low-risk, directly adjacent to the lines already being rewritten.
- [x] Removed the stale trailing comment in `sample.override.env` pointing at the old
      `renegademaster` image's docs page (dead link now that we build our own image).
- [~] **`docker build` / live bring-up: blocked in this sandbox**, not just untested. The `claude`
      account has no access to `/var/run/docker.sock` (`permission denied`) and no passwordless
      sudo, so `docker build`/`docker run` cannot execute here at all. Did the best available
      substitute instead:
      - `docker compose -f compose.project_zomboid.yml config` (doesn't need the daemon) against
        scratch `.env`/`override.env` files — confirmed the YAML is valid and
        `SERVER_BRANCH`/`MAX_RAM`/image tag all resolve correctly.
      - Tested the `sed` Xmx patch and the conditional `-beta` logic directly against the real
        downloaded 42.19 files (see above) rather than through Docker.
      - **This still needs a real `docker build` + `crabbot project_zomboid up` + Steam client
        connection from a machine with actual Docker access** before calling Phase 2 verified
        end-to-end. Treat this as the first thing to do next session, or hand off to whoever has
        docker access on the host.
- [x] **SandboxVars.lua reconciliation: done and verified.** Continuing from the prior session's
      analysis (which found 58 real customizations and flagged `FirearmUseDamageChance` and
      `LootItemRemovalList` as needing a decision — see git history of this file for that raw
      list), this session:
      - Downloaded a fresh vendor `Apocalypse.lua` (see reproduction commands below) and confirmed
        the 58 customizations were unchanged from the prior analysis.
      - Renamed `VERSION` → `Version` (casing-only, same value `6`).
      - Added the 3 keys vendor gained since our file was last touched: `SkillBookLoot = 0.6`,
        `RecipeResourceLoot = 0.6` (both loot-category sliders, comment/range copied from the
        existing identical-pattern loot options), and `ZombieLore.DoorOpeningPercentage = 0`
        (percentage tier option, same style as the existing `SprinterPercentage`; range/tiers
        confirmed from `media/lua/client/OptionScreens/ServerSettingsScreen.lua`'s
        `advancedCombo` definition).
      - **`FirearmUseDamageChance` resolved**: pulled the option's tooltip and enum labels from
        `media/lua/shared/Translate/EN/Sandbox.json` — it's now a 3-way choice (`1` = Disabled,
        `2` = Zombies only, `3` = All types of target), replacing the old boolean. Our old
        `true` meant "on for everything," which maps to `3`, not vendor's new default of `2` —
        set to `3` to preserve the actual customization rather than silently drifting to the new
        vendor default. Documented inline in the file.
      - **`LootItemRemovalList` resolved**: the same translation file confirms the option still
        exists in the engine with the exact tooltip already in our file
        ("A comma-separated list of item types that won't spawn as ordinary loot.") — it's just
        not set by the `Apocalypse.lua` preset (uses the engine's own blank default). Not an
        orphaned/removed key; left unchanged.
      - Verified with a small script that flattens both files into dotted key paths: merged file
        now has **exact 269/269 key parity** with vendor (only intentional divergence being the
        retained `LootItemRemovalList`), and all 58 customizations are still present with
        unchanged values.
- [x] **`configs/PigeonGrindhouse.ini` vendor-diff: done and verified** (this was listed as an
      open question in the prior session; resolved this session). Since Indie Stone doesn't ship
      a static default `.ini` template, generated a real one by running the actual downloaded
      `ProjectZomboid64` server binary directly (no Docker needed — it's a self-contained Linux
      ELF + bundled JRE) for ~20s with a scratch `$HOME`, which writes a fresh default
      `Server/<name>.ini` on first boot. Diffed against `configs/PigeonGrindhouse.ini`:
      - **Removed 7 dead keys** no longer present in the engine at all: `AutoCreateUserInWhiteList`,
        `ServerImageLoginScreen`, `ServerImageLoadingScreen`, `ServerImageIcon` (all were
        empty/false in our file — no real customization lost), and `AntiCheatFire`,
        `AntiCheatRecipe`, `AntiCheatServerCustomization` (deprecated anti-cheat checks; the
        remaining anti-cheat keys keep our hardened value of `4`).
      - **Added 5 new keys** vendor gained: `AnnounceAnimalDeath=false`, `War=false` (a master
        toggle now sits alongside the existing `WarStartDelay`/`WarDuration`/
        `WarSafehouseHitPoints`), `DiscordChatChannel=`, `DiscordLogChannel=`,
        `DiscordCommandChannel=`, and `MaxPacketsPerSecond=300` (new network anti-cheat option).
      - **1 real rename with a semantic narrowing**: `DisableSafehouseWhenPlayerConnected` →
        `DisableSafehouseWhenOwnerConnected` — the comment changed from "if a *member* of the
        safehouse is connected" to "if an *owner* of the safehouse is connected," so this is a
        behavior change, not just a rename. Value (`false`) carried over as-is; flagging here in
        case the distinction matters for how the group actually uses safehouses.
      - **1 split**: the old `DiscordChannel` + `DiscordChannelID` pair was replaced by the three
        separate `DiscordChatChannel`/`DiscordLogChannel`/`DiscordCommandChannel` keys above. Our
        old values were both empty, so nothing to carry over besides the rename.
      - **1 range expansion**: `MapRemotePlayerVisibility` gained a new tier (`3 = Friends and
        nearby players`, pushing "Everyone" from `3` to `4`) — comment updated, value (`1`)
        unaffected.
      - Verified with the same key-parity approach as SandboxVars: **exact 143/143 key match**
        against the freshly-generated default, with the 13 remaining value diffs all being
        confirmed intentional customizations (world seed, server/player IDs, password, public
        visibility, anti-cheat hardening, safehouse settings) — none accidental.
  - To reproduce the ground-truth lookups above in a fresh session (scratch downloads don't
    persist): `curl -sSL -o steamcmd.tar.gz
    https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz && tar -xzf
    steamcmd.tar.gz`, then `./steamcmd.sh +login anonymous +app_info_update 1 +app_info_print
    380870 +quit` for the branch list, or `./steamcmd.sh +force_install_dir <dir> +login
    anonymous +app_update 380870 validate +quit` (no `-beta` tracks `public`; ~7GB,
    anonymous/free, no docker needed) to get real server files. For the SandboxVars diff, use
    `media/lua/shared/Sandbox/Apocalypse.lua` and `media/lua/shared/Translate/EN/Sandbox.json`
    (tooltips/enum labels). For the INI diff, there's no shipped template — instead run the
    server directly to generate one: from the install dir, `export
    LD_LIBRARY_PATH="$PWD/linux64:$PWD/natives:$PWD:$PWD/jre64/lib/amd64" && export
    PATH="$PWD/jre64/bin:$PATH" && HOME=/some/scratch/dir timeout 25 ./ProjectZomboid64
    -servername configgen -adminusername admin -adminpassword admin`, then read
    `$HOME/Zomboid/Server/configgen.ini` (the real `$HOME`, not `-force_install_dir`, is where
    Zomboid writes config — override `$HOME` to keep it out of your real profile, and delete the
    scratch `$HOME/Zomboid` dir afterward). No root/sudo required for any of this.
- [x] Confirmed the `HEALTHCHECK`'s `pgrep "ProjectZomboid"` matches the running process name —
      **verified live**, not just statically, using the same directly-run server binary as above.
      `ps` shows the process `comm` truncated to 15 characters (`ProjectZomboid6`, since
      `ProjectZomboid64` is 16 chars), and `pgrep "ProjectZomboid"` (14 chars, substring match by
      default) matched the live PID correctly. No change needed.

### Phase 3 — Dockerfile / compose optimization pass

- [x] **Removed the dead `environment:` entries** (`GAME_VERSION`, `PAUSE_ON_EMPTY`,
      `PUBLIC_SERVER`, `USE_STEAM`) left over from the old `renegademaster` image contract that
      `entry.sh` never read.
- [x] **Wired `install.scmd` into `entry.sh`** instead of deleting it (2026-07-30). It's a
      steamcmd script, not a shell script, so steamcmd never expanded its `${STEAMAPPDIR}` /
      `${STEAMAPPID}` / `${SERVER_BRANCH}` references — those were always literal text, meaning
      even if something had invoked this file before, it would have been broken. Rewrote it with
      `__PLACEHOLDER__`-style tokens and had `entry.sh` render them via `sed` into
      `${HOME}/install.rendered.scmd` before calling `steamcmd.sh +runscript` on it (replacing the
      old inline `steamcmd.sh +app_update ...` invocation). Also:
      - Flipped `@ShutdownOnFailedCommand 0` → `1` — the old value told steamcmd to keep going
        (and `quit` cleanly) even if `app_update` failed, which combined with `entry.sh`'s
        `set -e` would have masked a failed update and launched the server on stale/incomplete
        files instead of aborting the container.
      - Added a guard in `entry.sh` that fails loudly if any `__PLACEHOLDER__` token survives
        rendering (e.g. from a future edit to `install.scmd` that adds a new placeholder without a
        matching `sed` line), instead of passing steamcmd a script with literal garbage in it.
      - `install.scmd` is now also mountable read-only over `/home/steam/install.scmd` (commented
        `volumes:` line in `compose.project_zomboid.yml`) so it can be edited without a rebuild.
      - **Not yet verified against a real `docker build` + container run** — same Docker-access
        blocker as the rest of Phase 2 (see below). Test this alongside that.
- [x] **Promoted the non-secret, actually-used runtime knobs out of the Dockerfile/override.env
      and into `compose.project_zomboid.yml`'s `environment:` block** (2026-07-30): `SERVER_BRANCH`,
      `SERVER_NAME`, `MAX_RAM`. Cross-checked against what `entry.sh` actually reads (grepped for
      every `${VAR}` reference) rather than guessing from the Dockerfile's `ENV` list — several
      Dockerfile `ENV` vars (`STEAM_VAC`, `GENERATE_SETTINGS`, `DEFAULT_PORT`, `UDP_PORT`,
      `RCON_PORT`, `CONFIG_DIR`) are never read by `entry.sh` either and are still dead; left them
      alone since removing them wasn't asked for this round, but they're the same class of
      leftover as the `environment:` entries just removed above — worth a follow-up.
      `environment:` in compose takes precedence over both the Dockerfile's baked-in `ENV` default
      and `env_file:`, so this also means any stale value left in the real (gitignored,
      unreadable-to-this-session) `override.env` — e.g. an old `SERVER_BRANCH` pin — is now
      silently overridden rather than winning. Recommend deleting any such stale lines from the
      real `override.env` for clarity even though they're now dead, and reserving `override.env`
      for genuinely secret values (`ADMIN_USERNAME`/`ADMIN_PASSWORD`).
- [ ] Reconcile the Dockerfile's `EXPOSE` list against `compose.project_zomboid.yml`'s `ports:`
      and Project Zomboid's actual required ports; drop or add entries so the two agree and
      nothing unused is published.
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
- ~~Does Indie Stone's 42.20 stable release actually require a `-beta` branch name at all~~ —
  **Resolved**: dropping `-beta` entirely (empty `SERVER_BRANCH`) tracks default/public, verified
  live against Steam's branch list on 2026-07-27. See Phase 2.
- ~~Is `get_changes.sh` still wanted at all now that `crabbot` exists, or should it just be
  deleted~~ — **Resolved 2026-07-30**: kept, minus the `mod_manager.py -gen` call (see Phase 1) —
  it's now just `git pull` + `crabbot project_zomboid update`, which is still a real convenience
  over running both by hand.
- What's the actual host RAM budget available for `MAX_RAM`? Now that it's actually wired up
  (Phase 2), this matters for real — 8192m is a safe floor matching vendor default, but our
  100+-mod list may want more. Needs the real host's available memory to size correctly. (Phase 2.)
- ~~`LootItemRemovalList`/`FirearmUseDamageChance` resolution~~ — **Resolved 2026-07-29**:
  `LootItemRemovalList` is still a live engine option, just unset by the `Apocalypse.lua` preset;
  `FirearmUseDamageChance` is now a 3-way enum and our old `true` was mapped to `3` ("all types of
  target") to preserve intent. See Phase 2.
- ~~Does `PigeonGrindhouse.ini` need the same vendor-diff treatment as `SandboxVars.lua`~~ —
  **Resolved 2026-07-29**: yes, and it's done — see Phase 2 (7 keys removed, 5 added, 1 rename
  with a semantic change, 1 split, 1 range expansion).
- **New**: is the `DisableSafehouseWhenOwnerConnected` semantic narrowing (was "any member" of the
  safehouse, now specifically "the owner") actually what the group wants, or was the old
  member-based behavior relied upon? Worth a quick check with players before going live, since
  it's a real behavior change baked into the rename, not just cosmetic. (Phase 2.)
- Ground-truth downloads this session came back as Steam buildid `24438606` (matching the `42.19`
  branch) rather than the `public` branch's own reported buildid `24449161` — likely CDN
  propagation lag right at the 42.20 launch moment rather than a download mistake. Worth a spot
  re-check of SandboxVars/INI parity once 42.20 is unambiguously live everywhere, though config
  schemas rarely change within a stable point release. (Phase 2.)

## Risks / rollback

- Build 42 saves are incompatible with Build 41 — bringing the server up on 42.20 effectively
  starts a fresh world. Confirm with the group before Phase 2 goes live on the real server, and
  back up the existing `${APPDATA}/zomboid/server-files` and `${APPDATA}/zomboid/config`
  directories first regardless.
- The Dockerfile fixes in Phase 2 (COPY paths, `SERVER_BRANCH` passthrough) are prerequisites for
  the image to build at all — if Phase 2 is rushed without them, `docker build`/`crabbot
  project_zomboid update` will fail outright.
- Rollback for Phase 2: the old `42.13.1` pin turned out to reference a Steam branch that no
  longer exists (verified 2026-07-27), so there's no working old image tag to fall back to as-is.
  If 42.20 has launch-week issues, fall back via `SERVER_BRANCH` — Indie Stone's own
  `legacy41` (Build 41) or `42.19` (last unstable checkpoint) branches — rather than trying to
  resurrect the old pin.
- This whole Phase 2 branch of work is currently uncommitted in the working tree (see status note
  at the top of the Phase 2 section) — nothing has been pushed or is live, so there's nothing to
  roll back yet; reverting just means discarding the 6 modified files (plus this plan doc) if
  needed.
- The `DisableSafehouseWhenOwnerConnected` rename (see Open questions) carries a real semantic
  narrowing from the old `DisableSafehouseWhenPlayerConnected` — if the group actually relied on
  "any member" locking a safehouse rather than just the owner, this is a behavior regression to
  watch for after going live, not just a config typo risk.
