# AzerothCore WotLK Private Server — Project Context

Small private server for a group of friends. WotLK 3.3.5a, native Debian install,
running the **liyunfan1223 playerbots fork** (not upstream AzerothCore).

## Layout

| What | Where |
|---|---|
| Source tree | `/home/gailin/azerothcore-playerbots` |
| Build dir | `/home/gailin/azerothcore-playerbots/build` |
| Installed binaries | `/home/gailin/azeroth-server/bin` |
| Configs | `/home/gailin/azeroth-server/etc` |
| Status page / scripts | `/opt/server-status` |

Custom module source lives under `azerothcore-playerbots/modules/`. Custom code is
**not** in a git repo — it is packaged straight from local disk by the deployment kit.

## Git / GitHub

- `origin` remote = upstream `liyunfan1223/azerothcore-wotlk` (read-only in
  practice - no push access there).
- `fork` remote = `git@github.com:HavocBuilt/Azerothcore-Skullcrusher.git`,
  the actual push target. Current branch `Playerbot` tracks `fork/Playerbot`.
- The deployment kit (`/home/gailin/deployment-kit/`) is its own separate git
  repo, pushed to `git@github.com:HavocBuilt/Skullcrusher-Redeploy.git`
  (`main` branch) - unrelated to the AzerothCore source, don't conflate them.
- Pushing works via a dedicated SSH key (`~/.ssh/github_skullcrusher`,
  configured in `~/.ssh/config` for `github.com`) added to the HavocBuilt
  GitHub account. No `gh` CLI is installed and no git identity is persisted
  in git config (by design - commits use `-c user.name=HavocBuilt -c
  user.email=jasonwalden@gmx.com` per-commit rather than a global config
  write). Creating/merging PRs currently means using the GitHub web UI
  directly (or a link like
  `github.com/HavocBuilt/Azerothcore-Skullcrusher/compare/master...Playerbot`)
  - there's no API access for it yet.

## Build

From `azerothcore-playerbots/build/`, configured with (per `CMakeCache.txt`):

```
cmake ../ -DCMAKE_INSTALL_PREFIX=/home/gailin/azeroth-server \
          -DAPPS_BUILD=all \
          -DMODULES=static \
          -DSCRIPTS=static \
          -DTOOLS_BUILD=none \
          -DWITH_WARNINGS=OFF \
          -DUSE_COREPCH=ON \
          -DUSE_SCRIPTPCH=ON \
          -DWITH_DYNAMIC_LINKING=OFF \
          -DBUILD_TESTING=OFF
make -j<N>
```

(`<N>` = however many cores you want to give it; not recorded in the cache.)

**Always ask before `make install` or restarting worldserver.** See Operating rules below.

## Services

Both run as systemd units with auto-restart:

- `authserver`
- `worldserver`
- `server-status-check.service` — runs `check_status.sh`, posts auth/world up-down
  alerts to a Discord webhook and serves a static HTML status page on **port 8090**.
  It also reports real players online, filtering out bots by the `rndbot` account
  name prefix. Discord roster posts are debounced: 5 minutes of stability before
  it announces.

Useful: `journalctl -u worldserver -f` for live logs.

## Database

Plain **MySQL** (deliberately not MariaDB). Databases:

- `acore_auth`
- `acore_characters`
- `acore_world`
- `acore_playerbots`

You can query these directly with `mysql -e "..."` rather than asking me to
copy-paste results. Credentials for this come from `~/.my.cnf` - if that file
is ever missing, plain `mysql`/`mysqldump` invocations silently fall back to
auth-as-OS-user, which fails, and the daily/weekly backup scripts in
particular fail *silently* (they log "Skipping db (not found)" and exit 0,
so the systemd timer shows success while producing empty backups). Check
`~/.my.cnf` exists first if a backup run looks suspiciously fast or its
dump files look suspiciously small.

`mysqld`'s `bind-address` is restricted to this server's own Tailscale IP
(`100.108.4.38`) only - not `0.0.0.0`, not `127.0.0.1`. Every `*DatabaseInfo`
connection string on the box (worldserver.conf x3, authserver.conf,
dbimport.conf, playerbots.conf's separate `PlayerbotsDatabaseInfo`) must use
that Tailscale IP, never `127.0.0.1` or `localhost` - `127.0.0.1` won't
connect at all now. The X Plugin (`mysqlx`, port 33060) is explicitly OFF.

**Hard-won lesson - keep every DatabaseInfo line in sync.** mod-playerbots
has its *own* separate DB connection (`PlayerbotsDatabaseInfo` in
`playerbots.conf`, distinct from `WorldDatabaseInfo`), and `dbimport.conf`
has its own copy too. Both were found on stale install defaults (wrong host,
wrong password) during a password rotation, invisible until a MySQL restart
dropped every connection - worldserver stayed up and looked healthy (bots
kept simulating off already-loaded in-memory data) while silently holding
zero live connections to `acore_world` or `acore_playerbots`. Check
`information_schema.processlist` grouped by `db` after any MySQL restart to
confirm all four databases actually have live connections, not just
`acore_auth`/`acore_characters`. Whenever the acore DB password (or host)
changes, all five connection strings need updating together, not just the
three in worldserver.conf.

Tuning already applied: `skip-log-bin`, raised `innodb_buffer_pool_size`,
`innodb_flush_log_at_trx_commit=2`, NVMe-aware settings.

OS-level tuning: `vm.swappiness=10`, Transparent Huge Pages disabled
(`never`, via `disable-thp.service` - InnoDB doesn't opt in via `madvise()`
so THP is a pure latency-spike risk for it), CPU governor pinned to
`performance` via `cpu-governor-performance.service` (persists across
reboot; plain `cpupower frequency-set` does not - there's no
`cpupower.service` shipped on Debian, unlike some other distros).

Automated backups run every other day over Tailscale to a NAS, covering all four
databases plus configs.

## Modules installed

Per `AC_MODULES_LIST`/`CONFIG_FILE_LIST` in
`build/src/server/apps/CMakeFiles/worldserver.dir/flags.make` — this is what's
actually compiled into the current `worldserver` binary:

- `mod-playerbots` — the core of the server; ~525 bots run stable on the current
  CPU. Config: `playerbots.conf`
- `mod-ah-bot-plus` — AH bot is GUID 806 on a **dedicated separate account**
  (works around the same-account auction restriction; don't "fix" this).
  Config: `mod_ahbot.conf`
- `mod-multibot-bridge` — server-side only despite the name; adds finer control
  over `mod-playerbots` in group and raid contexts. Config: `MultiBotBridge.conf`
- `mod-npc-buffer` — creature entry 601016. Config: `npc_buffer.conf`
- `mod-npc-services` — custom C++ service NPC, creature entry **900000**. No
  config file.
- `mod-npc-trainer` — consolidates all profession trainers into one NPC with a
  gossip menu. No config file.
- `mod-homebrew-gm`. Config: `HomebrewGM.conf`
- `mod-pvp-titles`. Config: `mod_pvptitles.conf`
- `mod-weekendbonus` — 1.25x multiplier. Config: `mod_weekendbonus.conf`
- `mod-bot-watchdog` — custom. Detects bots stranded by an interrupted taxi flight
  (`UNIT_STATE_IN_FLIGHT` ending far from any `TaxiNodes.dbc` entry) and recovers
  them by teleporting to the nearest flight master. Bots can't self-recover the way
  a real player would, hence this. Config: `BotWatchdog.conf`
- `mod-alt-autosell` — auto-sells grey (poor quality) items, separately tunable
  for playerbot alts vs. real players (min/max quality, announce toggle);
  replaces the old `mod-junk-to-gold`. Config: `mod_alt_autosell.conf`
- `mod-levelup-events` — spawns Crier Goodman (NPC entry 2198) with green
  fireworks to congratulate a player at admin-configured milestone levels;
  milestones live in an `acore_world` table, no rebuild needed to add or change
  one. Config: `mod_levelup_events.conf`
- `mod-gmisland-rest` — grants rest XP (tavern flag) to real players while on GM
  Island and teleports playerbots home instead of letting them linger there. No
  config file.
- `mod-racial-trait-swap` — lets a player pay gold, via NPC 98888, to swap out
  their racial traits. Config: `RacialTraitSwap.conf`
- `mod-reagent-bank-account` — server-backed reagent bank for trade goods, gems,
  and crafting materials; requires the matching client addon, no banker NPC.
  Config: `mod_reagent_bank_account.conf`

**Removed:** `mod-ollama-chat` and the local Ollama install are gone. Don't suggest
re-adding them or assume Ollama is available.

## Key config values

Do not change these without asking — they're tuned, not defaults:

- `MapUpdate.Threads=4`
- `AiPlayerbot.BotActiveAlone=10`
- `AiPlayerbot.RandomBotMaxLevel=60`
- `MaxPrimaryTradeSkill=11`
- Server-level cap: **60**

Hardware: Ryzen 3 PRO 5350G, NVMe. A CPU upgrade is planned but tuning the current
chip comes first.

## Custom content

Three custom mount items for specific players:

| Entry | Player | Mount | Spell |
|---|---|---|---|
| 90000 | Jay | Mekgineer's Chopper | 60424 |
| 90001 | Jon | Big Blizzard Bear | 58983 |
| 90002 | Gord | Swift Spectral Tiger | 42777 |

**Hard-won lesson — mount item SQL.** A working mount item needs two spell effect
slots, with `spellid_1=483` / `spelltrigger_1=0`, and `spellcharges_1=0` (**not -1**).
Getting `spellcharges_1` wrong produces an item that looks correct server-side but
does nothing on right-click. If a new mount item misbehaves, check this first.

Also note: some mount problems are client-side (MPQ / `Item.dbc`), not server-side.
Correct SQL plus no in-game reaction points at the client patch, not the database.

## Client side

The WoW 3.3.5a client is on a separate Windows 11 machine (`gailin-cosplay`,
Tailscale `100.70.140.13`). Server is reachable at Tailscale `100.108.4.38`.

There's a custom launcher: a PowerShell script compiled to a windowless `.exe`,
styled after the official WoW launcher (branded look, real-time byte-level progress
bar, status text). It checks for MPQ changes over plain HTTP from the server and
replaces the local copy. It reads an external config file so it doesn't need a
recompile, auto-detects the WoW folder, and uses a custom icon with a rounded
borderless window.

Pending: map/vmap/mmap/dbc extraction from a 3.3.5a client on a Windows PC using
AzerothCore's extractor tools, then `scp` to the server's data directory.

## Operating rules

1. **There is no maintenance window.** The group plays at scattered hours and one
   player is in Australia. Never restart `worldserver` on your own initiative —
   propose it and wait.
2. **Ask before destructive SQL.** `UPDATE`/`DELETE` on `acore_characters` in
   particular. Reads are fine.
3. **Explain the why, not just the what.** Short answers, but say what a change
   does and why it's the right one.
4. **Step-by-step.** One change at a time, confirmed, rather than a large batch.
5. Prefer editing files in place over printing patches for me to paste.

## Open items

- Alt characters auto-questing and levelling via the playerbots altbot system.
- AdiBags is the chosen combined-bag addon for players (auto-sorts into categories).

A deployment kit already exists at `/home/gailin/deployment-kit/` (`deploy.sh`,
see its README), covering both migration/DR (full mode) and handing a clean copy
to a friend (template mode). Map/vmap/mmap/dbc data is copied from this server
rather than re-extracted on the target. It always reads live state (configs,
systemd units, git commits) at run time rather than keeping stale copies, so
there's nothing to "refresh" when this server's tuning changes.
