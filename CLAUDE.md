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
- **Hard-won lesson — purely custom modules deploy via rsync, not their own git
  repo.** `deployment-kit`'s `sync-source.sh` gives a module its own git
  checkout on the target (clone + checkout matching SHA) only when that
  module's directory has a `.git`; modules with no `.git` fall back to a raw
  rsync copy. The script's own comment calls that fallback a rare/defensive
  case, but in practice every fully hand-written module on this server —
  `mod-levelup-events`, `mod-npc-services`, `mod-gmisland-rest`,
  `mod-alt-autosell`, `mod-bot-watchdog`, `mod-npc-trainer` — has no `.git` at
  all and always takes the rsync path. That's expected and fine (`deploy.sh`
  picks up whatever's currently on disk automatically, nothing to commit
  anywhere for a change to travel), not a gap to fix — don't go looking for a
  missing commit for these modules the way you would for `mod-playerbots` or
  `mod-ah-bot-plus`, which do have their own checkouts.

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

**A module-only change is not a full rebuild.** Because `MODULES=static`, editing
one file under `modules/<mod>/src/` recompiles just that translation unit and
relinks `worldserver` - minutes, not hours. Keep the stages separate so a failure
is attributable and the live server stays up until the last moment:

1. `nice -n 10 make -j6` - **no `install`**. This builds into the tree only; the
   running server keeps its old binary and nothing is swapped. Use fewer jobs than
   cores: `worldserver` is serving on the same 8-core box and saturating all of
   them lags the game for whoever is online.
2. Confirm the change is really in the new binary instead of trusting the exit
   code - `nm -C build/src/server/apps/worldserver | grep <NewSymbol>`, or
   `strings` for a new literal.
3. `cp -a` the installed binary aside first, so rollback is a copy rather than a
   rebuild.
4. `make install`, then the restart by hand (Operating rules rule 1).

**A new module needs a cmake reconfigure, and that rebuilds every module.** Run `cmake ..` in
`build/` (the cached options are kept). It regenerates
`modules/gen_scriptloader/static/ModulesLoader.cpp`, so all modules recompile, all of
`mod-playerbots` included: roughly an hour at `-j3`/`-j6` on this box, not minutes.
`AC_MODULES_LIST`, which the startup DB updater uses to find each module's
`data/sql/db-world/`, is baked in at configure time. A new module's SQL is therefore only
auto-applied by a binary built after the reconfigure.

**Pausing a build for players — launch it in its own session.** Even under `nice -n 10`, a
`-j6` build lagged the game for Jon (playing from Australia) on 2026-09-14. `kill -STOP` on a
`make` started from an ordinary background shell does **not** pause it. The wrapper shell
sees the child stop, exits, and the stopped, now-orphaned process group gets SIGHUP and dies;
the log shows `exit=147`. Nothing is lost, since re-running `make` resumes where it stopped.
For a real pause, start the build as
`setsid bash -c 'echo $$ > build.pgid; exec nice -n 10 make -j3 worldserver'`, then use
`kill -STOP -<pgid>` and `kill -CONT -<pgid>`. Before resuming an interrupted build, check that
the newest `.o` files are non-empty and readable by `nm`. Checking for real players online
before starting a long build avoids the problem entirely.

`make install` does not clobber live configs - AzerothCore installs `.conf.dist`
files and leaves an existing `.conf` alone.

**`make install` is not a plain copy — don't read a `cmp` mismatch as a bad install.**
It re-runs the build first, and the git revision stamp (`GitRevision.cpp`) is often
regenerated, which relinks **both** `worldserver` and `authserver` and installs both
(the running authserver is unaffected until its own next restart). CMake also rewrites
the RUNPATH on install: the build-tree binary carries a placeholder of colons, the
installed one `/home/gailin/azeroth-server/lib` — exactly 31 bytes, so
`cmp -l | wc -l` = 31 with identical sizes is the expected result. Verify the installed
binary by searching it for a new string literal instead (e.g. Python `mmap.find`).

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

**Hard-won lesson — a DB password rotation orphaned a hardcoded credential, and
it failed silently for three days.** `check_status.sh` held `DB_USER`/`DB_PASS`
inline. The September 2026 rotation updated `~/.my.cnf` and the worldserver configs
but nothing swept standalone scripts, so the notifier's player query began returning
`Access denied`. Because that query ended in `2>/dev/null` the error vanished,
`$PLAYERS` came back empty, and the script substituted `"none"` - and a roster of
"none" never *changes*, so it never posted. The symptom was indistinguishable from
"nobody is online," which is why nobody noticed.

Three rules follow, and they outlive this one script:

- **Never `2>/dev/null` a query that needs credentials.** It converts an auth
  failure into a plausible-looking empty result. Let it fail loudly into
  `journalctl` instead.
- **`--defaults-extra-file` must be the FIRST option on a mysql command line.**
  Placed after `-h` it fails with
  `mysql: [ERROR] unknown variable 'defaults-extra-file=...'`.
- **After any credential rotation, sweep for hardcoded copies** - the config files
  are not the only place one lives. A `grep -rl <old-password> /home /etc /opt` is
  enough. Done for the September rotation: `check_status.sh` was the only live
  casualty; the remaining hits are `~/.my.cnf.bak`, `~/.bash_history`, and
  pre-rotation config copies under `backups-weekly/*/configs/`. Live configs clean.

The notifier's credential now lives in `/root/.acore-status.cnf` (mode `600`,
root-owned) and is passed with `--defaults-extra-file`, so the next rotation is one
edit in one place. Keep it out of the script. Note this fix is local to this box -
if the deployment kit ever rebuilds `/opt/server-status` from a template, check the
template carries it rather than the old inline password. Both notifier paths are
verified end to end since the fix: the roster post, and the auth/world up-down alert
(fired on the 2026-09-13 22:25 worldserver restart and confirmed arriving in Discord).

**Diagnosing the status notifier - read the state files' mtimes before the code.**
`status.json` is rewritten every run (~30s), but `last_state.txt` and
`last_players.txt` are written **only when their value changes**. Comparing the three
mtimes localizes a fault in seconds without opening the script: all three fresh means
healthy; `status.json` fresh while `last_players.txt` is days stale means the script
is running fine and the roster path specifically is dead. `/tmp/discord_payload.json`
and `/tmp/discord_players_payload.json` are written immediately before each `curl`,
so their mtimes show when a send was last *attempted* - which separates "never
reached the webhook" from "the webhook rejected it." To test a webhook's validity
without posting anything, `GET` it: `200` plus a JSON object means it is alive,
`404` with code `10015` means it was deleted.

Useful: `journalctl -u worldserver -f` for live logs.

**Hard-won lesson — `Console.Enable = 1` under systemd burns a whole core.** The unit
gives `worldserver` `/dev/null` as stdin, so `readline()` in `CliThread`
(`src/server/apps/worldserver/CommandLine/CliRunnable.cpp:205`) returns EOF instantly,
the command is empty, and the loop goes straight back round. Result: one thread pinned
at 100% CPU and 30-50k lines of bare `AC>` per minute (~450 KB/s) in the journal, which
also bloats it (3.9 GB when found). It hides well — total worldserver CPU near 200%
reads as normal bot load, and it predated whatever change was being checked at the
time. Fixed 2026-09-13 by setting `Console.Enable = 0` in `worldserver.conf` (backup:
`worldserver.conf.bak-20260913-console`); nothing is lost since no tty is attached
anyway. Verified after the 22:54 restart: zero `AC>` lines in the journal, one fewer
thread (15 vs 16), and no thread near 100%. If the spam ever returns, check that
`Console.Enable` wasn't reset by a config regenerated from `.conf.dist` (default is 1).

**Technique — find a hot thread without pausing the server.** Don't attach `gdb` to the
live `worldserver` (a 2.3 GB RelWithDebInfo binary; symbol loading freezes the game for
everyone). Instead snapshot every thread's `wchar` from `/proc/<pid>/task/*/io` and
`utime+stime` (fields 14+15) from `task/*/stat`, wait a few seconds, snapshot again,
and diff. A thread with huge write growth and ~100% CPU is a spinning logger/console;
the four `MapUpdate.Threads` at ~80% each are normal with the bots running.

**Check the journal, not just `Server.log`, for config problems at boot.**
`worldserver.conf` is parsed before the log appenders exist, so anything wrong with it
(e.g. `Config::LoadFile: Duplicate key name ...`) is printed only to stdout and lands in
`journalctl -u worldserver --since <start>`, never in `Server.log`. Module configs load
after logging is up, so their warnings appear in both. A `Server.log`-only grep on
2026-09-13 found the `playerbots.conf` duplicate and silently missed a duplicate
`Appender.Playerbots` in `worldserver.conf` that had been warning on every boot.

**`Server.log` and `Errors.log` are rewritten on every boot, not appended.** Read them
whole after a restart; a line count taken before the restart points past the end of the
new file and a `tail -n +N` silently returns nothing.

**Known startup log noise — not faults, don't chase them:**

- `SmartWaypointMgr::LoadFromDB: Path entry 476220, unexpected point id N, expected N-1`
  (51 lines, N = 10..60) — Windsor's escort path is missing point 9 in `waypoints`, the
  gap described in the `waypoints`/`waypoint_data` lesson below. The path still runs.
- `Config::LoadFile: Failed open file ...` / `Config: Missing property ...` for
  `BotWatchdog`, `mod_dungeon_quest_guide`, `mod_levelup_events` and `MultiBotBridge` —
  those modules only have a `.conf.dist` installed, so the built-in defaults apply.
  Copy the `.dist` to `.conf` only if a value needs changing.
- `Skill condition specifies invalid skill value` and the 46 `RequiredSkillPoints`
  lines — see the level-60-cap note under the master profession trainer.
- `[1213] Deadlock found when trying to get lock; try restarting transaction` (once,
  some boots only — first seen 2026-09-14 04:03) — a race in stock startup mail cleanup.
  `World.cpp:848-849` sends `DELETE mi FROM mail_items mi LEFT JOIN mail m ... WHERE m.id
  IS NULL` and `UPDATE mail m LEFT JOIN mail_items mi ... SET m.has_items=0` back to back
  with async `CharacterDatabase.Execute`, so they can run at the same time on two
  connections and lock `mail` rows in opposite order. MySQL rolls one back, and plain
  `Execute` is not retried (only transactions are, in `Transaction.cpp`). Harmless: both
  run again on the next boot, and after the 04:03 occurrence there were 0 orphan
  `mail_items` rows. To see which statements collided, `SHOW ENGINE INNODB STATUS\G` and
  read the `LATEST DETECTED DEADLOCK` section (the `acore` user can run it).
- `Creature entry (900000) has SmartAI enabled but no SmartAI entries in the database.` —
  King Varian's `creature_template.AIName` is `SmartAI`, although all of his behaviour is C++
  (`npc_multi_service`). Harmless, and already present on boots before 2026-09-14 08:19.
- `Creature (Entry: 1749) has assigned gossip menu 900185, but npcflag does not include
  UNIT_NPC_FLAG_GOSSIP (1).` — Lady Prestor, from the Onyxia attunement work; already present
  before 2026-09-14 08:19. Not investigated. If Prestor's gossip ever fails to appear, start
  here.

**`Playerbots.log` is empty on purpose — don't "restore" the stock `Logger.playerbots`
line.** `worldserver.conf.dist` ships `Logger.playerbots=5,Console Playerbots`; level 5
is **Debug**, and with ~525 bots sending that to `Console` would flood the journal the
same way the `Console.Enable` spin did. The live `worldserver.conf` has no
`Logger.playerbots` line (its slot at line 713 had been overwritten with a duplicate of
the `Appender.Playerbots` line, which was removed 2026-09-13; backup
`worldserver.conf.bak-20260913-dupappender`), so the `playerbots` category falls back to
`Logger.root=2` — errors only, to `Console Server`. If bot logs are ever needed for a
debugging session, add a temporary `Logger.playerbots=4,Playerbots` (Info, file only, no
`Console`) and remove it afterwards.

**No remote console access.** `SOAP.Enabled = 0` in `worldserver.conf`, and
`worldserver` runs as a plain systemd `simple` service with no attached
tty/tmux/screen session. There is no way to send in-game GM commands (e.g.
`.reload smart_scripts` after a `smart_scripts` edit) from the terminal —
someone has to run them from an in-game GM account, or `worldserver` needs a
full restart to pick up DB changes on its own. Don't try to hunt for a
console workaround; just ask for the in-game reload or a restart.

**There is no `.reload npc_text`.** The reload command table in
`src/server/scripts/Commands/cs_reload.cpp` has `conditions`, `creature_text`,
`creature_template`, `gossip_menu`, `gossip_menu_option`, `smart_scripts` and
`npc_text_locale` — but no plain `npc_text`. So a new or edited gossip *greeting body*
only appears after a full worldserver restart, even though the menu, the clickable
options and their conditions all hot-reload fine. When building gossip-driven content,
expect the option to work immediately and the greeting paragraph to be missing until the
next restart, and don't go hunting for a bad `TextID` over it. Check this command table
before promising that any given table can be reloaded live. (`.reload trainer` does
exist and reloads `trainer`, `trainer_spell` and `creature_default_trainer` together —
`cs_reload.cpp:767`.)

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
  CPU. Config: `playerbots.conf`. `AiPlayerbot.DisabledWithoutRealPlayer = 1`: random bots
  log in only 30 s after a real player does and log out 300 s after the last one leaves. So
  **0 characters online after a restart with nobody real on is expected, not a fault.**
  Confirm with `information_schema.processlist` that `acore_playerbots` has connections
  instead.
- `mod-ah-bot-plus` — AH bot is GUID 806 on a **dedicated separate account**
  (works around the same-account auction restriction; don't "fix" this).
  Config: `mod_ahbot.conf`
- `mod-multibot-bridge` — server-side only despite the name; adds finer control
  over `mod-playerbots` in group and raid contexts. Config: `MultiBotBridge.conf`
- `mod-npc-buffer` — creature entry 601016. Config: `npc_buffer.conf`
- `mod-npc-services` — custom C++ service NPC, creature entry **900000**. Also teaches
  Aspect of the Lone Wolf to Hunters level 20+ (see `mod-lone-wolf`). No config file.
- `mod-npc-trainer` — consolidates all profession trainers into one NPC (Doctor Who,
  900001) with a gossip menu, backed by 14 private trainer entries 900003-900016 —
  see the Doctor Who section under Custom content. No config file.
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
  fireworks to congratulate a player at admin-configured milestone levels, and
  independently can grant an item and/or gold reward at configured levels
  (currently: a Portable Hole + gold at 40/60, gold only at 70/80). Both the
  milestones and the rewards live in `acore_world` tables (`levelup_events`,
  `levelup_event_rewards`), no rebuild needed to add or change one — only a
  worldserver restart to pick up table changes. Config: `mod_levelup_events.conf`
- `mod-gmisland-rest` — grants rest XP (tavern flag) to real players while on GM
  Island and teleports playerbots home instead of letting them linger there. No
  config file.
- `mod-racial-trait-swap` — lets a player pay gold, via NPC 98888, to swap out
  their racial traits. Config: `RacialTraitSwap.conf`
- `mod-reagent-bank-account` — server-backed reagent bank for trade goods, gems,
  and crafting materials; requires the matching client addon, no banker NPC.
  Config: `mod_reagent_bank_account.conf`
- `mod-dungeon-quest-guide` — custom (hand-written, no `.git`, rsync-deployed). On a
  player entering a non-raid dungeon instance, summons a Dungeon Quest Guide (creature
  **900002**, greeting `npc_text` 900002 / 900003) next to the nearest
  `areatrigger_teleport` landing point. Its gossip lists that dungeon's quests the
  player can take right now and adds the chosen one straight to the log; it does not
  take turn-ins. A quest qualifies when `QuestSortID` = the dungeon's zone, it has a real
  starter, and that starter has no C++ `ScriptName` or SmartAI `ACCEPTED_QUEST` (19) row
  (those start escorts/scenes the guide would bypass — 438 skipped at load). Hand
  corrections go in `acore_world.dungeon_quest_guide_override` (`include` 1 forces a quest
  into `zone_id`, 0 excludes it everywhere), picked up on restart. Config
  (`DungeonQuestGuide.Enable`, default on): only the `.conf.dist` is installed.
  Pre-module rollback binary: `bin/worldserver.pre-dungeon-guide`.
- `mod-lone-wolf` — custom (hand-written, no `.git`, rsync-deployed). The AuraScript and
  `spell_dbc` rows for the Hunter spell Aspect of the Lone Wolf (900002-900004); see its
  section under Custom content. No config file. Pre-module rollback binary:
  `bin/worldserver.pre-lone-wolf`.

**Custom creature entries in use:** 900000 (`mod-npc-services`, renamed in the DB to
"King Varian Wrynn <Hero of Azeroth>" by `~/rename_service_npc.sql` — same NPC),
900001 (Doctor Who, `mod-npc-trainer`), 900002 (Dungeon Quest Guide), 900003-900016
(Doctor Who's 14 profession trainers), 900017 (Garret Hollis, Northshire hunter trainer),
900018 (Ada Brightwood, Goldshire hunter trainer). The next new custom NPC should take
**900019** or higher — check `creature_template` first. Other key spaces are separate and
don't collide: `npc_text` 900002/900003 are the guide's greetings, and `trainer` ids
900003-900016 are Doctor Who's trainer lists (stock trainer ids stop at 126). Custom
quest ids start at **900100** (900100-900104 are the Human Hunter taming chain; stock
quest ids stop at 26034), and spawn guids 5300900/5300901 are the two hunter trainers.
Spell ids are yet another separate key space. Custom `spell_dbc` ids 900002-900004 are Aspect
of the Lone Wolf; the three mount spells are 90000-90002 in `Spell.dbc`, and `spell_dbc`
otherwise tops out at 100102. The DBC loader sizes the spell index table to the highest id,
so going from 100102 to 900002 cost about 7 MB of pointers. That's harmless, but worth knowing
when picking the next id.

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

**Hard-won lesson — AzerothCore module reward code (gold/item grants).**
`Player::ModifyMoney()` takes copper, not gold — multiply the gold amount by
10000 before calling it. For granting an item that might not fit (bags full),
don't hand-roll a `MailDraft`/`Item::CreateItem`/transaction sequence —
`Player::SendItemRetrievalMail(itemEntry, count)` already does that correctly
(creates the item, saves it, mails it from "The Postmaster") and validates the
item entry for you. This is what `mod-levelup-events`' reward feature uses as
its bags-full fallback. Also: `ChatHandler::PSendSysMessage()` takes `fmt`-style
`{}` placeholders, not printf `%u`/`%d`.

**Master profession trainer — Doctor Who `<Know It All>` (creature 900001).**
Script `npc_master_profession_trainer` in `mod-npc-trainer` (hand-written, no
`.git`, rsync-deployed). Gossip lists all 14 professions; picking one summons that
profession's private trainer (entries **900003-900016**, "Alchemy <Grand Master
Trainer>" etc.) onto the player as a temporary summon and opens its trainer window,
despawning 10s after the player leaves interaction range with a 5 minute failsafe.
Spawned **only on GM Island** (map 1, guid 5300744) and meant to stay there — it is a
private convenience for the owner and friends, not public content, so don't offer to
give it a city spawn.

**Hard-won lesson — the stock profession-trainer entries don't teach Northrend
recipes.** Until 2026-09-13 Doctor Who summoned 33608-33623, which an old comment called
"Dalaran grandmaster trainers". They are not: they're plain "Alchemy"/"Mining" NPCs
spawned in Outland (map 530) using the *Master*-tier `trainer_spell` lists, which stop
around skill 325-375 — so the Grand Master rank was granted but most 376-450 recipes
(and e.g. Smelt Cobalt/Saronite/Titanium) could never be learned. In the stock data the
complete lists are scattered: each profession's Grand Master list is on named Northrend
trainers (several of whom are quest givers, so summoning a copy would drag their quests
along), specialization recipes live only on specialist trainers, and the complete
Alchemy (65) and Enchanting (94) lists have no creature at all. Don't judge a trainer by
its subname or a code comment — count its `trainer_spell` rows and `MAX(ReqSkillRank)`.

The fix is `data/sql/db-world/npc_master_profession_trainer_grandmaster_lists.sql`:
copies of the 33608-series templates (model, faction, addon, locales) as 900003-900016,
each with its own `trainer` (id = entry) whose list is the union of every stock
`trainer.Type = 2` trainer whose rows are mostly that skill, deduplicated with the
cheapest row winning (stock duplicates only differ in price). It is built with
`INSERT ... SELECT` and temporary tables, so it needs to run as one mysql session (the
DB updater does this) and was dry-run inside `START TRANSACTION ... ROLLBACK` first — a
module SQL file that errors at startup stops worldserver from booting. Result: 1557
rows, zero stock tradeskill recipes missing, e.g. Alchemy 97, Blacksmithing 248,
Engineering 178, Inscription 234. Specialization recipes keep their `ReqAbility`, so the
window only lets a player learn their own specialization's. ReqLevel was left alone:
six Engineering recipes (five Goblin, plus Turbo-Charged Flying Machine) need level
65/70 and stay unlearnable at the level-60 cap. Recipes from drops, vendors and
reputation are outside any trainer list by nature. Rollback binary:
`bin/worldserver.pre-trainer-lists`.

The same change fixed the confirmation message, which used printf `%s` and printed
literally — the `PSendSysMessage` placeholder lesson above, found in the wild.

Selecting a profession also grants every tier Apprentice -> Grand Master by casting
the trainer teach-spells as *triggered* (`player->CastSpell(player, spellId, true)`),
which bypasses both the level and the skill-rank gate. The skill **value** is
untouched - only the ceiling moves, so 1->450 is still raised by crafting.

**Why the bypass is required, not just convenient.** `MaxPlayerLevel = 60` on this
realm, but the Grand Master teach-spells require level 65. That tier is therefore
structurally unreachable here by any amount of levelling or travel - a normal
trainer can only ever reach Master (skill 375). The same config is why 46
`RequiredSkillPoints ... max possible skill is 300` lines appear in `Errors.log` on
every boot (AzerothCore derives that check's ceiling from `MaxPlayerLevel * 5`);
they are pre-existing noise about Northrend profession quests, not a fault.

**Hard-won lesson — there are TWO `Spell.dbc` files on disk and they differ.**
`DataDir = "./data"` in `worldserver.conf` means the server loads
`azeroth-server/bin/data/dbc/`. The copy at `azeroth-server/bin/dbc/` is stale, has
a *different field layout* (so a parser tuned to one silently mis-reads the other),
and is missing spells outright. Always parse `bin/data/dbc/`; the live file is the
full 3.3.5a layout, 234 fields, spell name at field 136.

**Hard-won lesson — resolve profession tier spells against `trainer_spell`, not
DBC names.** Several professions have duplicate old/new teach-spells with identical
names. Engineering's Grand Master is **61464**, not 51305 (51305 exists and is named
correctly but no trainer uses it); Cooking, First Aid and Fishing have the same
trap. Take whichever ID `trainer_spell` actually references. The verified ladder:

| Profession | Skill | Apprentice | Journeyman | Expert | Artisan | Master | Grand Master |
|---|---|---|---|---|---|---|---|
| Alchemy | 171 | 2275 | 2280 | 3465 | 11612 | 28597 | 51303 |
| Blacksmithing | 164 | 2020 | 2021 | 3539 | 9786 | 29845 | 51298 |
| Cooking | 185 | 2551 | 3412 | 54257 | 18261 | 54256 | 51295 |
| Enchanting | 333 | 7414 | 7415 | 7416 | 13921 | 28030 | 51312 |
| Engineering | 202 | 4039 | 4040 | 4041 | 12657 | 30351 | 61464 |
| First Aid | 129 | 3279 | 3280 | 54254 | 10847 | 54255 | 50299 |
| Fishing | 356 | 7733 | 7734 | 54083 | 18249 | 54084 | 51293 |
| Herbalism | 182 | 2372 | 2373 | 3571 | 11994 | 28696 | 50301 |
| Inscription | 773 | 45375 | 45376 | 45377 | 45378 | 45379 | 45380 |
| Jewelcrafting | 755 | 25245 | 25246 | 28896 | 28899 | 28901 | 51310 |
| Leatherworking | 165 | 2155 | 2154 | 3812 | 10663 | 32550 | 51301 |
| Mining | 186 | 2581 | 2582 | 3568 | 10249 | 29355 | 50309 |
| Skinning | 393 | 8615 | 8619 | 8620 | 10769 | 32679 | 50307 |
| Tailoring | 197 | 3911 | 3912 | 3913 | 12181 | 26791 | 51308 |

**Hard-won lesson — module SQL applied by hand gets reapplied on next startup.**
`Updates.EnableDatabases = 7` means the startup updater scans
`modules/*/data/sql/db-world/`. A file applied manually with `mysql <` is not
recorded in `acore_world.updates`, so the updater sees it as new and runs it on the
next boot. That is safe only because these files are written `DELETE` then `INSERT`;
keep module SQL idempotent for exactly this reason.

**Editing an already-applied module SQL file re-runs the whole file on the next boot.**
`Updates.Redundancy = 1`, so the updater compares each recorded file's hash with the
file on disk and, if it changed, logs `>> Reapplying update "<file>" '<old>' -> '<new>'
(it changed)...` and applies it again (`UpdateFetcher.cpp:350`). Every statement runs,
not just the edited part. So to change what a module has already applied, **add a new
file** in its `data/sql/db-world/` and leave the old one alone, unless re-running all of
the old one is genuinely harmless. Example: Doctor Who's Grand Master lists went into a
new `npc_master_profession_trainer_grandmaster_lists.sql` because editing
`npc_master_profession_trainer.sql` would also have deleted and re-inserted Doctor
Who's GM Island spawn. (The updater scans `db-world/` recursively, so `base/`,
`updates/` or the folder root all work.)

**Dry-run module SQL before a restart — and know when a rollback can't undo it.** A
module SQL file that errors during the startup update stops worldserver from booting,
so prove it first by piping one mysql session:
`START TRANSACTION;` / `source <file>` / check queries / `ROLLBACK;`, then re-count
afterwards to confirm nothing persisted. This is only a true dry run if the file has no
statements that **implicitly commit**: `CREATE TABLE` (including `IF NOT EXISTS`),
`ALTER TABLE`, `DROP TABLE`, `TRUNCATE`, `RENAME TABLE` all commit immediately, taking
every earlier statement in the transaction with them. `CREATE TEMPORARY TABLE` and
`DROP TEMPORARY TABLE` do not. Four existing module files contain `CREATE TABLE IF NOT
EXISTS` (`dungeon_quest_guide.sql`, `levelup_events.sql`,
`2026_09_09_00_levelup_event_rewards.sql`, `mod_reagent_bank_account_NPC.sql`) — dry-run
those against a scratch copy of the database, or with the DDL stripped out, never
directly in a transaction on `acore_world`.

**Human Hunters (race 1, class 3), added 2026-09-14.** Stock 3.3.5a has no Human Hunter.
The server half is three re-applicable files in `data/sql/custom/db_world/`, applied by
the updater as `CUSTOM` (tracked in git through a `.gitignore` exception; upstream
ignores that folder). The client half is `CharBaseInfo.dbc` in `patch-4.mpq` — see
"Client side".

| File | Adds |
|---|---|
| `2026_09_14_00_human_hunter.sql` | `playercreateinfo` (Northshire start), action bar, Guns in `playercreateinfo_skills`, `skillraceclassinfo_dbc` rows 117/133/632 (hunter Axes/Guns/Daggers with the Human bit), `charstartoutfit_dbc` 368/369 (copy of the Dwarf Hunter outfit) |
| `2026_09_14_01_human_hunter_trainer_northshire.sql` | Garret Hollis <Hunter Trainer> 900017, trainer 8 (levels 2-6, same as Coldridge), guid 5300900 in the Northshire Abbey yard |
| `2026_09_14_02_human_hunter_taming_the_beast.sql` | Ada Brightwood <Hunter Trainer> 900018, trainer 7 (full list), guid 5300901 beside Erma in Goldshire; quests 900100-900104; taming-rod conditions and SmartAI credit (below); Erma (6749) gains the quest giver flag; Young Forest Bear (822) gets `AIName = SmartAI` |

Both trainers use gossip menu 7262 (the Draenei hunter trainers' menu) because the
Dwarf trainers' menus are written in dialect. Their positions were taken from nearby
spawns, not measured in game — fix with `.gps` and update the SQL file (re-applying it
is harmless, every block is DELETE then INSERT).

**Hard-won lesson — a new race/class combination needs `SkillRaceClassInfo`, not just
`playercreateinfo`.** The server accepts any race/class with a `playercreateinfo` row,
but `ObjectMgr` silently drops `playercreateinfo_skills` rows whose skill
`GetSkillRaceClassInfo` doesn't allow for that combination, and the player can never
hold the skill either. The stock hunter rows for Axes, Guns and Daggers leave out the
Human bit (Bows and Crossbows don't). Check every skill against *all* existing races of
the class, not one. The fix needs no DBC edit: AzerothCore's `*_dbc` world tables
(`skillraceclassinfo_dbc`, `charstartoutfit_dbc`, `chrraces_dbc`, ...) override DBC rows
with the same `ID` at load (`DBCDatabaseLoader.cpp`).

**Hard-won lesson — Taming the Beast quests hardcode their quest id in spell data.** A
taming rod casts a dummy-aura spell (e.g. 19674); when the aura ends successfully, a
`switch` in `SpellAuraEffects.cpp` casts a final spell (e.g. 19677) that charms the beast
and has a `QUEST_COMPLETE` effect naming the stock quest (6064). Which creature a rod
works on is a `conditions` row (source 17, type 31). New quests can't be credited by
those spells, and new spells would have to go into both the server and client
`Spell.dbc`, which differ on this realm. The Human chain reuses the Dwarf rods instead:
an `ElseGroup` 1 condition adds the Elwynn beast, and the beast's SmartAI catches the
final spell (`SPELLHIT`, event 8) and runs `CALL_AREAEXPLOREDOREVENTHAPPENS` (action 15)
on the invoker. Two traps: the charm is already on the beast when `SpellHit` is
delivered and SmartAI ignores events on charmed creatures, so the row needs
`event_flags` 512 (`SMART_EVENT_FLAG_WHILE_CHARMED`); and the loader drops action 15
unless the quest has `SpecialFlags` 2. (A hunter's charm keeps the creature's AI
enabled; only a warlock charming a demon turns it off, in `Unit::SetCharmedBy`.)

| Quest | Step | Beast (entry) | Rod | Final spell |
|---|---|---|---|---|
| 900100 | The Hunter's Path: Stormwind hunter trainers 5515-5517 → Ada (`BreadcrumbForQuestId` 900101) | | | |
| 900101 | Taming the Beast | Stonetusk Boar (113) | 15911 | 19677 |
| 900102 | Taming the Beast | Gray Forest Wolf (1922) | 15913 | 19676 |
| 900103 | Taming the Beast, rewards Tame Beast | Young Forest Bear (822) | 15908 | 19597 |
| 900104 | Training the Beast: Ada → Erma, rewards Beast Training | | | |

**Aspect of the Lone Wolf (Hunter spell 900002), added 2026-09-14.** A toggled Hunter aspect
that gives +20% damage done (all schools), -10% damage taken, +5% dodge, +5% parry and +50%
mana regeneration, only while the hunter has no living pet, so a petless ranger isn't strictly
worse. Stock Hunter spells and talents are untouched; another player mains Hunter. The spec
and balance rationale are in `/home/gailin/attunement/aspect-of-the-lone-wolf-spec.md`. If it
tests too strong, lower the damage figure first.

| Spell | Role | Lives in |
|---|---|---|
| 900002 | The visible aspect. One effect: `SPELL_AURA_PERIODIC_DUMMY` (226), 1000 ms period, carrying the AuraScript. Class mask `0 / 0x400000 / 0`, level 20, category 47 (the shared 1 s aspect cooldown). | `spell_dbc` + client `Spell.dbc` |
| 900003 | Hidden passive: aura 79 +20% damage done (bp 19, school mask 127), 87 -10% damage taken (bp -11), 49 +5% dodge (bp 4) | `spell_dbc` only |
| 900004 | Hidden passive: aura 47 +5% parry (bp 4), 110 +50% mana regen (bp 49, MiscValue 0 = mana) | `spell_dbc` only |

Everything is in `modules/mod-lone-wolf/`: `src/mod_lone_wolf.cpp`
(`spell_hun_aspect_of_the_lone_wolf`), plus three DELETE-then-INSERT files in
`data/sql/db-world/` (the 900003/900004 rows, the 900002 row, and the `spell_script_names`
binding). The script re-evaluates on apply and on every tick: Hunter, alive, and no living pet
means `AddAura` 900003/900004, otherwise remove them. On any removal of 900002 (aspect swap,
death, logout, cancel) it strips both.

It is taught by a gossip option on King Varian (900000, GM Island, `mod-npc-services`), shown
to Hunters level 20+ who don't know it yet; the handler checks again before `learnSpell`,
since a client can send an option it was never shown. It is deliberately **not** on a trainer
list: stock trainer 7 is shared by 35 hunter trainers, and playerbots'
`PlayerbotFactory::InitAvailableSpells` teaches random bots every spell on every class trainer
list valid for them (`AiPlayerbot.AutoLearnTrainerSpells = 1`). The pre-edit
`mod_npc_services.cpp` is in `~/backups/20260914-pre-lone-wolf/`.

**The client row is hand-edited and must agree with the server rows.** 900002's row in
`patch-4.mpq` is a copy of Aspect of the Hawk (13165) with these changes:
- name, description and aura tooltip rewritten with the exact numbers
- effect 1 = aura 226, period 1000, bp -1
- effect 2 cleared (Hawk's proc: trigger spell 6150 and proc flags)
- class mask `0 / 0x400000 / 0`
- spell and base level 20

If a balance value changes, change 900003/900004 **and** the tooltip. A tooltip that doesn't
match the actual effects means the two have drifted.

Hard-won lessons, each verified in the source on 2026-09-14:

- **Hunter aspects are mutually exclusive through the class mask, not `spell_group`.**
  `spell_group` holds no aspect except 53746. `SpellInfo::LoadSpellSpecific` makes any
  Hunter-family spell whose `SpellClassMask` hits `0x00380000 / 0x00440000 / 0x00001010` a
  `SPELL_SPECIFIC_ASPECT`, and only one of those survives per caster. Borrowing an aspect's
  bit also borrows every talent keyed on it: the Hawk, Monkey, Cheetah and Viper bits are hit by
  Improved Aspect of the Hawk, Aspect Mastery, Kindred Spirits and others. **Aspect of the
  Wild's bit (`SpellClassMask_2 = 0x400000`) appears in no `Spell.dbc` class mask and no
  `spell_proc` row**, and its three C++ checks are in damage paths for other families, which is
  why 900002 uses it. The converse matters too: helper auras must carry **no** aspect bit, or
  they cancel the aspect.
- **Spell value = `EffectBasePoints` + `EffectDieSides`, so DieSides must be 1** for "stored
  value is one less" to hold: +20% is 19, -10% is -11. Stock Defensive Stance (7376) stores
  its -10% that way. Also set `EquippedItemClass = -1` on a `spell_dbc` row; the column
  defaults to 0.
- **Passive auras are never sent to the client** (`Aura::CanBeSentToClient`), so server-only
  helper spells need no client DBC row. But passives also **survive death**
  (`RemoveAllAurasOnDeath` skips them) and are **not saved** at logout. Whatever applies them
  must remove them, which here is `AfterEffectRemove` on 900002; after login the next tick
  re-applies them.
- **A script-driven periodic check needs `SPELL_AURA_PERIODIC_DUMMY` (226) with a period.** A
  plain `SPELL_AURA_DUMMY` (4) never calls `OnEffectPeriodic`.
- **There is no pet dismiss or pet death script hook** in this fork, only
  `PetScript::OnPetAddToWorld`; hence the 1-second tick.
- **A dead hunter pet stays in the pet slot** (`Pet::Update`: "hunters' pets never get removed
  because of death"), so "has a pet" must also check `IsAlive()`. The script resolves
  `GetPetGUID()` with `ObjectAccessor::GetCreatureOrPetOrVehicle`, not `GetGuardianPet()`,
  because the latter logs a fatal error and clears the slot when the GUID doesn't resolve.
  Snake Trap snakes don't occupy the pet slot, so they don't cancel the bonus.
- **A self-targeted `PERIODIC_DUMMY` aura counts as a buff.** `_IsPositiveEffect` has no case
  for aura 226, so the aspect can be right-clicked off with no `spell_custom_attr` row.

Ongoing custom quest recreation work (the "Skullcrusher Attunement Project," rebuilding
the classic Onyxia attunement chain) lives at `/home/gailin/attunement/` as a numbered
log of diagnostic/fix SQL scripts (`NN_description.sql`), applied directly to
`acore_world`, one confirmed step at a time rather than in a repo. Those scripts'
header comments document the invocation as `mysql -h... -uacore -p acore_world`, but
`~/.my.cnf` makes a plain `mysql acore_world < NN_file.sql` work without prompting —
prefer that.

**Map of the Windsor / Onyxia chain as currently wired**, since it spans several
creatures and is easy to get lost in:

| Quest | Name | Starter → Ender |
|---|---|---|
| 4282 | A Shred of Hope | 9023 → 9023 |
| 4322 | Jail Break! | 9023 → (escort completion) |
| 6402 | Stormwind Rendezvous | 9560 → 17804 |
| 6403 | The Great Masquerade | 17804 Squire Rowe → Varian (starter moved in 84, ender in 76) |

Marshal Windsor is creature entry **9023**, spawn guid 47622 on map 230 (BRD), and is
the quest starter for 4242, 4282 and 4322. He is *no longer* the starter for 6403 — see
the lesson below on quest-starter tables. His escort path is `waypoints.entry = 476220`.
His `smart_scripts` live at `entryorguid = 9023, source_type = 0`, ids 0-4 and 6-8 (id 5,
the old self-teleport, was retired in script 84 and the gap is harmless — SmartAI iterates
whatever rows it finds and does not need contiguous ids). The throne room conversation is
timed action list **902300** (`source_type = 9`).

**Hard-won lesson — `creature_queststarter`/`creature_questender` key on creature
*entry*, not spawn guid, so never let a shared dungeon spawn start a quest whose
content happens elsewhere.** 6403 was originally wired with Windsor (9023) as its
starter. Entry 9023 has exactly one world spawn — the caged one in the BRD Detention
Block — so after handing 6402 to Squire Rowe in Stormwind, the only way to pick up The
Great Masquerade was to fly all the way back into Blackrock Depths. There is no way to
scope a quest starter to one spawn of an entry; the only fix is to give the quest to an
NPC who is already standing where the player ends up (here Rowe, entry 17804, who is
also 6402's ender, so the handoff is immediate) and **summon** the scene NPC in.

The corollary is the more important half: **never use `SMART_ACTION_TELEPORT` to
relocate a shared world spawn into a later scene.** Script 77 did exactly that — on
accepting 6403, Windsor teleported himself from his cell to the Stormwind throne room —
which stripped the BRD cell out from under every other player still running Jail Break
until his respawn. Summoning a temporary copy at the scene location instead costs
nothing, leaves world state alone, and resets `SMART_EVENT_FLAG_NOT_REPEATABLE` gating
for free, since each run gets a fresh creature rather than one persistent spawn.

Two related gotchas found alongside it:

- **`SMART_EVENT_ACCEPTED_QUEST` (19) fires on the creature the player accepted the
  quest *from*.** Once the starter moved to Rowe, Windsor's own accept-triggered rows
  became permanently unreachable — not broken, just never called. Check which NPC owns
  the accept event before hanging logic off it.
- **Prefer triggering a summon on quest *accept* rather than quest *reward* of the
  previous step.** Rowe's original row fired on rewarding 6402, a one-shot: once that
  summon's despawn timer expired there was no way to get the NPC back and the player was
  pushed toward the old spawn again. Firing on accept means abandoning and retaking the
  quest re-summons him, so the step is always recoverable.

**Hard-won lesson — making a SmartAI escort NPC actually fight (three separate
blockers, found the hard way on Marshal Windsor / Jail Break).** All three must be
right; any one of them silently produces "the NPC just stands there", with no error
and no log line:

1. **`SMART_ACTION_ESCORT_START` (53) param6 is `reactState`, and it is applied
   unconditionally.** `SmartScript.cpp` does a bare
   `me->SetReactState((ReactStates)e.action.wpStart.reactState)`, and
   `REACT_PASSIVE = 0` — so leaving param6 at its default 0 makes the escort passive
   the instant it starts. Then `CreatureAI::UpdateVictim()`, which `SmartAI::UpdateAI`
   calls at the top of every tick, hits `else if (me->GetVictim()) me->AttackStop();`
   for passive creatures. A forced `SMART_ACTION_ATTACK_START` does work — and gets
   stripped back off one tick later. **Set param6 = 2 (REACT_AGGRESSIVE).**
2. **The faction has to be mutually hostile with the mobs, and "friendly NPC" factions
   usually aren't hostile to anything.** `SMART_TARGET_CLOSEST_ENEMY` resolves through
   `Creature::SelectNearestTarget` → `NearestHostileUnitCheck` → `IsValidAttackTarget`,
   so a non-hostile faction yields *zero* targets and `ATTACK_START` no-ops silently.
   Don't guess faction numbers — parse `bin/dbc/FactionTemplate.dbc` (plain WDBC: 20-byte
   header, then 14 uint32 fields per record — `id, faction, flags, ourMask, friendMask,
   hostileMask, enemyFaction[4], friendFaction[4]`) and check
   `A.hostileMask & B.ourMask` both directions, with `enemyFaction`/`friendFaction`
   as overrides. Windsor's original 534 and a "fix" to 1733 both had
   `hostileMask` of 0 and 4 respectively vs. Dark Iron's `ourMask = 8` — neither could
   ever fight. **250 ("Escortee") is the right general answer**: hostile to monsters,
   hostile to neither Alliance nor Horde players. Prefer applying it with
   `SMART_ACTION_SET_FACTION` (2) on the quest-accept event rather than on
   `creature_template`, so the NPC stays inert (and unaggroable) before it's freed.
3. **The engage radius is a leash, not a detection range — keep it small (~10yd).**
   `SMART_ACTION_ATTACK_START` lands in `SmartAI::AttackStart`, which explicitly tears
   out the escort path (`MovementExpired()` / `StopMoving()` / `Clear(false)` when the
   active motion slot is `ESCORT_MOTION_TYPE` or `POINT_MOTION_TYPE`) and replaces it
   with an unbounded `MoveChase`. So every yard of radius is a yard the NPC will
   abandon its route to travel. 30yd sent Windsor across the Detention Block to
   Gerstahn and out the east garrison door, where he got lost and died and failed the
   quest. At 10yd he engages what's on the path and returns to his waypoints.

Corollary about debugging order: with blockers 1 and 2 both in play, *nothing* about
the engage script can be validated — a previous pass here widened the radius 10yd →
30yd and wrote down "10 was too tight", a conclusion drawn entirely from a symptom the
faction bug was causing. When a SmartAI change produces no observable effect, suspect a
silently-empty target list or a state being reset downstream before you tune numbers.
Also: `creature_template.faction` gates every attack/assist validity check regardless of
`type_flags & CREATURE_TYPE_FLAG_CAN_ASSIST` — that flag alone is never enough.

**Note on `flags_extra = 2` (`CREATURE_FLAG_EXTRA_CIVILIAN`).** It makes
`Creature::CanStartAttack` return false outright, so the NPC has no native aggro at all
and only fights when a script explicitly tells it to. That is usually what you want for
a scripted escort — it keeps all combat under one deterministic, phase-gated,
radius-capped trigger instead of having core aggro and the script disagree about how far
the NPC will wander. It does *not* interfere with threat or retaliation (nothing in the
threat system checks it). Note that `Creature::UpdateMoveInLineOfSightState()` returns
early for anything with `AIName = 'SmartAI'`, so the civilian branch there never runs for
these NPCs — the `CanStartAttack` check is the one doing the work.

**Debugging note — check the test character before changing world data.** A quest
appearing when it shouldn't is often character state, not a broken chain. "The Great
Masquerade" (6403) showed up on Windsor at the BRD cell because the test character had
already been rewarded its prerequisite 6402 during earlier testing, while 4322 had been
reset — the `PrevQuestID` wiring was correct the whole time. Query
`character_queststatus` / `character_queststatus_rewarded` first. `.quest remove <id>`
does clear the rewarded flag (`cs_quest.cpp` calls `RemoveRewardedQuest`), so resetting
a test character needs no SQL.

**Hard-won lesson — gate escort combat behavior with SmartAI phases, not just
quest state.** An escort NPC that's dormant (e.g. caged) before the quest is
accepted needs its periodic engage script to require `event_phase_mask = 1` (or
another phase bit) rather than running unconditionally (`event_phase_mask = 0`).
Set that phase via a `SMART_ACTION_SET_EVENT_PHASE` action fired on the same
`SMART_EVENT_ACCEPTED_QUEST` event that starts the escort. Without this, widening
the engage radius makes the NPC break character and attack through cage bars
before the player has even freed it.

**Hard-won lesson — verify SmartAI `action_type`/`event_type` values against the
local source tree, don't recall them from memory.**
`src/server/game/AI/SmartScripts/SmartScriptMgr.h` in `azerothcore-playerbots` is
ground truth — these constants shift between AzerothCore versions/forks, and a
wrong one doesn't error, it just silently wires up the wrong action. E.g.
`SMART_ACTION_SUMMON_CREATURE` is `12` in this tree, not the `11` a different
version might use. Grep the header for the exact constant before writing a
`smart_scripts` row, every time.

**Hard-won lesson — `waypoints` and `waypoint_data` don't share a key.**
`ESCORT_START`'s runtime path source (`SMART_WAYPOINT_MGR`) reads the `waypoints`
table, keyed by `entry`. `waypoint_data` is a separate source/editing table keyed
by its own generated `id`, unrelated to `waypoints.entry`. Deleting a point from
one without looking up the other's real key silently no-ops on the wrong table —
happened once already (a fix deleted a stray point from `waypoints` correctly,
but its matching `waypoint_data` delete used `id = <that waypoints.entry value>`
and matched zero rows), leaving a permanent point-numbering gap in one table that
the other didn't have. Always query for the real `waypoint_data.id` before
editing it.

**Technique — scripted multi-NPC dialogue sequences.** A `source_type = 9` timed
action list is the standard way to sequence several delayed lines: each row uses
`event_type = 60` (`SMART_EVENT_UPDATE` — the only timed-event type not gated by
in/out-of-combat state), `event_param1`/`event_param2` as the delay since the
*previous* row fired, and is kicked off via `SMART_ACTION_CALL_TIMED_ACTIONLIST`
on the owning creature (usually chained off an earlier event via that event's
`link` column). Within it, `SMART_ACTION_TALK` targeted at
`SMART_TARGET_CREATURE_GUID` (params: guid, entry; `useTalkTarget = 0`) makes
*that* creature speak the line, not the script's owner — so one NPC's script can
drive an entire cross-NPC conversation without adding any `smart_scripts` rows to
the other participants.

**Trigger scripted scenes from a gossip option, never from arrival.** A cutscene that
auto-fires when its NPC teleports or reaches a waypoint will be half over before players
who are still running to the spot can see it, and there is no way to replay it. Put it
behind a gossip option ("We are all here, Marshal.") so the players start it when they
are actually assembled. Working pattern, proven twice here (Prestor in script 50,
Windsor in 82): `npc_text` → `gossip_menu` → `gossip_menu_option` →
`SMART_EVENT_GOSSIP_SELECT` (62, params menuID + actionID, target
`SMART_TARGET_ACTION_INVOKER`), paired with a second row on the same event doing
`SMART_ACTION_CLOSE_GOSSIP` (72) so the scene isn't played behind a dialog box. Put
`event_flags = 1` (`SMART_EVENT_FLAG_NOT_REPEATABLE`) on the trigger row so a second
click can't restart the scene mid-play; it resets on respawn, which is usually the
behaviour you want. And gate the option in `conditions`
(`CONDITION_SOURCE_TYPE_GOSSIP_MENU_OPTION = 15`, `CONDITION_QUESTTAKEN = 9`) — one
creature entry often appears at several points in a chain (9023 is both the caged
Windsor in BRD and the Stormwind one), and an ungated option shows up at all of them.

**Hard-won lesson — a dead SmartAI stops processing its own timed action list.** If a
scripted scene ends with its owner dying, every row sequenced after the death silently
never fires. Structure the death as the last action on that creature's list, or better,
drive it from a *different* creature's list — in the Masquerade finale Windsor's list only
summons Lady Onyxia and despawns Prestor, then stops; she runs the kill and everything
after it from her own list, which is both mechanically safe and the faithful version of
the scene.

**`SMART_ACTION_SUMMON_CREATURE` (12) treats `target_x/y/z/o` as an OFFSET**, not as
absolute coordinates — the handler resolves the target list, then does `x += e.target.x`
against each target's own position. This is genuinely useful: target an existing creature
by `SMART_TARGET_CREATURE_GUID` with all four offsets at 0 and the summon appears exactly
where that creature stands, with no coordinates to drift if the spawn is ever moved.
When swapping one NPC for another, summon *before* despawning the original — once it's
gone it can no longer be resolved as a position target.

**But that is only true for target types that actually produce a target list.** Two
don't, and both take `target_x/y/z` as real coordinates instead:

- `SMART_TARGET_RANDOM_POINT` treats them as a source position to scatter around.
- `SMART_TARGET_POSITION` (8) falls through to `default: break` in `GetTargets`
  (`SmartScript.cpp:4226`), leaving the target list **empty**. The offset loop therefore
  never runs, and an explicit branch further down (`:1622`) summons at the literal
  `target_x/y/z/o`. This is the easy trap: the offset rule above is the documented
  behaviour and the more recent precedent in these scripts, so it is tempting to write
  offsets into a `SMART_TARGET_POSITION` row and get a summon at the wrong place with no
  error. Decide which of the two you are using and write the coordinates to match.

**Per-player summons are available in this fork** — `SmartActionSummonCreatureFlags`
(`SmartScriptMgr.h:734`): `PersonalSpawn = 1`, `PreferUnit = 2`, passed in
`SMART_ACTION_SUMMON_CREATURE`'s param6. `PreferUnit` makes the action invoker (the
player) the summoner rather than the script's owner, and `PersonalSpawn` then makes the
creature private to them — so param6 = 3 is the combination that yields a copy only that
player can see. **Caveat: the `SMART_TARGET_POSITION` branch at `SmartScript.cpp:1622`
does not pass `personalSpawn` through at all** — only the target-list and random-point
branches do. Using it therefore means anchoring the summon on a creature GUID with
offsets rather than on absolute coordinates.

**`SMART_ACTION_FORCE_DESPAWN` (41) takes `forceRespawnTimer` in param2 (seconds).**
Worth using deliberately: several key attunement NPCs (Windsor guid 47622, Prestor guid
5300750) ship with `spawntimesecs = 7200`, so a scene that despawns or kills one blocks
the whole chain for two hours for everyone else. Both are now on 300s.

**Standing limitation of the Masquerade finale:** Prestor is a single shared world spawn,
so while one player runs the throne room scene everyone else sees her missing. Acceptable
for this group with 5-minute respawns. Windsor is no longer part of this problem — since
script 84 he is a temporary summon rather than the relocated BRD spawn. The remaining fix
is the `PersonalSpawn` flag documented above, which is now known to be available; it is
smaller than previously assumed, but it does require re-anchoring the summon off absolute
coordinates onto a creature GUID.

**Schema note — creature display/model IDs live in `creature_template_model`**
(`CreatureID`/`CreatureDisplayID` columns), not on `creature_template` itself, in
this AzerothCore version.

**Schema note — the `creature` spawn table keys on `id`, not `id1`.** Some AzerothCore
versions (and most forum snippets) use `id1`/`id2`/`id3` for the difficulty-entry
columns; this tree has a single `id`. `quest_template_addon` likewise has no
`NextQuestInChain`, and `quest_template` has no `RequiredRaces` — check `DESC <table>`
rather than trusting a query copied from elsewhere.

**Where the DBCs actually are.** `worldserver` runs with working directory
`/home/gailin/azeroth-server/bin` (systemd `WorkingDirectory`, confirmed 2026-09-14 via
`/proc/<pid>/cwd`) and `DataDir = "./data"`, so the live DBC files are at
**`/home/gailin/azeroth-server/bin/data/dbc/`**. `bin/dbc/` is an older copy and is
stale — see the two-`Spell.dbc` lesson; other files differ too (e.g. `CharStartOutfit`
rows). Values can also be overridden by the `*_dbc` world tables, so check those as
well. Useful when a value isn't in MySQL at all —
faction templates, taxi nodes, spell data. They're plain WDBC: a 20-byte header
(`magic, recordCount, fieldCount, recordSize, stringBlockSize`) followed by fixed-size
records, trivially parsed with a few lines of Python.

**Recovering a pre-change value.** `/home/gailin/acore_world_backup_20260907.sql` is a
full pre-change `acore_world` dump. When a past script overwrote a column and didn't
record the original (e.g. `creature_template.faction` for 9023), scan the dump's
`INSERT INTO \`creature_template\`` line for the `(<entry>,...)` record rather than
guessing at what stock AzerothCore ships. It's ~306MB, so stream it, and count columns
against `DESC creature_template` to map the value.

## Client side

The WoW 3.3.5a client is on a separate Windows 11 machine (`gailin-cosplay`,
Tailscale `100.70.140.13`). Server is reachable at Tailscale `100.108.4.38`.

There's a custom launcher: a PowerShell script compiled to a windowless `.exe`,
styled after the official WoW launcher (branded look, real-time byte-level progress
bar, status text). It checks for MPQ changes over plain HTTP from the server and
replaces the local copy. It reads an external config file so it doesn't need a
recompile, auto-detects the WoW folder, and uses a custom icon with a rounded
borderless window.

**Client patch pipeline.** `~/wow-updates/` is served by `wow-updates-http.service`
(`python3 -m http.server 8080`). The launcher fetches `checksums.txt`, compares it with
the sha256 of the player's local `patch-4.mpq`, downloads `patch-4.mpq` only on a
mismatch, then fetches `patch-notes.lua` (the popup shows when `version` changes).
**Regenerate `checksums.txt` every time the MPQ changes** (`sha256sum patch-4.mpq >
checksums.txt`, run inside `wow-updates/`). It was left stale from 2026-08-30 to
2026-09-14, so launchers either re-downloaded the patch on every launch or kept an old
one. Back up all three files first (`~/backups/<timestamp>-pre-<change>/`) and put the
MPQ in place under a temporary name plus `mv`, so a launcher checking mid-copy never
gets half a file.

**What `patch-4.mpq` holds (2026-09-14):** nine spell DBCs, including a `Spell.dbc` with
custom content that is **not identical to the server's `bin/data/dbc/Spell.dbc`** —
never copy one over the other. It also holds `CharBaseInfo.dbc` with the Human Hunter
row. The three Dwarf taming rod spells (19674, 19687, 19548) have their enUS
description and aura tooltip pointed at generic "Begins taming a beast..." / "Taming
beast." strings appended to the string block, because the Human chain reuses them on
Elwynn beasts. Their names (cast bar) are unchanged.

**MPQ load order.** Later archives win, and letter patches load after numbered ones, so
`patch-k.MPQ` overrides `patch-4.mpq`. The players' `Data/` folder (server copy at
`~/wow-client-data-fixed/Data/`) has a third-party `patch-k.MPQ` that replaces the
character-create GlueXML and `CharStartOutfit.dbc`. So `CharStartOutfit` edits in
patch-4 are ignored: the creation preview shows no gear for a new race/class
combination, though the items the server grants come from `charstartoutfit_dbc` and are
unaffected. That creation screen gets class availability from the client API
(`GetAvailableClasses` / `IsRaceClassValid`, which read `CharBaseInfo.dbc`), so shipping
`CharBaseInfo.dbc` in patch-4 does work. Before shipping any DBC in patch-4, list every
client MPQ for that file.

**MPQ tooling without sudo or pip.** Nothing is installed. `apt-get download smpq
libstorm9 libtomcrypt1 libtommath1` into a scratch folder, `dpkg-deb -x` each into one
root, add a `libstorm.so.9 -> libstorm.so.9.22.0` symlink, and run `root/usr/bin/smpq`
with `LD_LIBRARY_PATH=root/usr/lib:root/usr/lib/x86_64-linux-gnu`. `smpq -l` lists, `-x`
extracts, and `smpq -a -f -C ZLIB <archive> DBFilesClient/X.dbc` (run from the folder
that contains `DBFilesClient/`) adds or replaces a file in place. Work on a copy, then
extract everything back out and compare md5s before deploying.

Pending: map/vmap/mmap/dbc extraction from a 3.3.5a client on a Windows PC using
AzerothCore's extractor tools, then `scp` to the server's data directory.

## Operating rules

1. **There is no maintenance window.** The group plays at scattered hours and one
   player is in Australia. Never restart `worldserver` on your own initiative —
   propose it and wait. Note this is also enforced by the box: there is no
   passwordless `sudo` rule (`/etc/sudoers.d/` holds only the stock README), so
   `sudo systemctl restart worldserver` fails with "a password is required" and the
   restart has to be run by hand — in this CLI, as `! sudo systemctl restart
   worldserver`. Don't burn time looking for a way around it. Checking for real
   players first is still worth doing: join `characters.online = 1` against
   `acore_auth.account` and exclude the `rndbot%` username prefix.
2. **Ask before destructive SQL.** `UPDATE`/`DELETE` on `acore_characters` in
   particular. Reads are fine.
3. **Explain the why, not just the what.** Short answers, but say what a change
   does and why it's the right one.
4. **Step-by-step.** One change at a time, confirmed, rather than a large batch.
5. Prefer editing files in place over printing patches for me to paste.

## Open items

- **Aspect of the Lone Wolf is verified server side but not yet in game.** Deployed
  2026-09-14 08:19. The three `mod-lone-wolf` SQL files were applied and recorded as `MODULE`,
  the script is bound to 900002, and neither the logs nor the journal show any Lone Wolf error.
  - **Still to do:** the client row for 900002 in `patch-4.mpq` has to be made by hand (field
    list in the Custom content section) and shipped with a regenerated `checksums.txt`.
  - **Before the patch:** a GM hunter can check the bonuses with `.aura 900003`; dodge should
    rise by 5%.
  - **After the patch:** run the spec's Phase 4 list:
    1. Learn it from Varian on GM Island.
    2. Check the tooltip matches the effects.
    3. With no pet, cast it and check the character sheet changes.
    4. Summon the pet: the bonuses go.
    5. Dismiss it, and separately let it die: the bonuses return in both cases.
    6. Cast Aspect of the Hawk: it cancels Lone Wolf.
    7. Relog with the aspect on: the state is correct.
    8. A non-Hunter can't learn it.
    9. No bot ever has it.
  - **If something fails:** if the bonuses never apply, check `spell_script_names` and the
    1-second tick first. If the numbers are right but the tooltip isn't, the client row has
    drifted.

- **Human Hunters are verified server side but not yet in game.** Deployed 2026-09-14
  03:19: the three SQL files applied as `CUSTOM`, "Loaded 63 Player Create
  Definitions", nothing in `Errors.log` about the new ids, and the new `patch-4.mpq` /
  `checksums.txt` / `patch-notes.lua` (version `2026-09-14-1`) are live; the previous
  three files are in `~/backups/20260914_025748-pre-human-hunter/`. To test: the
  launcher downloads the patch; Human → Hunter is selectable (preview without gear is
  expected); a new character starts in Northshire with the Dwarf Hunter gear, Auto Shot
  works, and Guns/Axes/Daggers are in the skill list; Garret Hollis and Ada Brightwood
  stand on the ground and train; at level 10 the taming chain completes, and the rod
  tooltip reads "Begins taming a beast". The least certain part is the taming credit: if
  a beast is tamed but the objective doesn't complete, start with `smart_scripts` id 10
  on 113/1922/822 and `SMART_EVENT_FLAG_WHILE_CHARMED`. Also worth noting in passing:
  stock `[DND] TAR` class trainers sit in phase 1 about 4 yards up in front of Northshire
  Abbey and in Goldshire (Arena Tournament realm leftovers) — unknown whether players
  see them.
  - **In game 2026-09-14: creation, Northshire start and titles work, but hunter trainers
    show an empty list.** Tested on Malcolm (guid 1126, Human Hunter, level 20 via
    HomebrewGM SET_LEVEL, 0 copper) at Garret Hollis (900017) and Ulfir Ironbeard (5516,
    GM Island). **The server side is ruled out:** the Train option appeared (no
    `GOSSIP_OPTION_TRAINER` error in `Errors.log`, where `Logger.sql.sql` writes), and
    replaying `Player::IsSpellFitByClassAndRace` against `bin/data/dbc` plus the
    `skillraceclassinfo_dbc` overrides passes all 172 spells of trainer 7 and all 5 of
    trainer 8 for Human, exactly as for Dwarf. Skills 50/51/163 have RaceMask 0xffffffff.
    `patch-4.mpq`'s `Spell.dbc` matches the server's numerically for every trainer spell.
    SET_LEVEL only dispatches `.character level` and teaches nothing, so "already knows
    everything" is ruled out too. The suspect is the client.
  - **Next, in game:** (1) the trainer window's Available/Unavailable/Used filter dropdown;
    (2) whether Malcolm's spellbook has the Beast Mastery/Marksmanship/Survival tabs and
    the skills panel lists them; (3) the same GM Island trainer with a non-Human hunter:
    if that sees spells and Malcolm doesn't, dig into the client's skill DBCs. Also ask
    whether "empty" means the training window opens with no spells, or the gossip has
    no training option. Malcolm needs gold before he can buy anything.
  - **Trap:** `~/azeroth-server/bin/dbc/` is a stale 3.2-era copy (222-field `Spell.dbc`,
    max spell id 57091) that the server does not load. `DataDir = "./data"` with
    `WorkingDirectory=bin`, so the live files are `bin/data/dbc/`. `~/wow-client-data-fixed`
    `locale-enUS.MPQ` holds that same old set and lacks the locale patch MPQs, so it is
    not a faithful copy of the players' client DBCs.
- **Doctor Who's Grand Master trainer lists (900003-900016) are verified server side but
  not yet in game.** Deployed 2026-09-13 23:51: SQL applied and recorded in `updates`,
  140 trainers / 820 default trainers loaded, no errors. To test: pick a profession from
  Doctor Who; the window should be titled "<Profession> <Grand Master Trainer>", list
  recipes up to 450 (above-skill ones greyed out), and chat should say "You are now a
  Grand Master of <Profession>." (no literal `%s`). Gailin's Alchemy at 306 is a good
  check — 306-325 recipes weren't reachable before. If a list looks wrong, fix the SQL
  file, apply it by hand (`mysql acore_world < file`, safe since it is idempotent) and
  run in-game `.reload trainer` — no restart needed for list-only changes. Editing the
  file changes its hash, so the updater re-applies it on the next boot too.
- **`mod-dungeon-quest-guide` has not been tested in game yet.** Server side is verified
  (SQL applied, creature 900002 and both greetings present, 163 zones indexed, no
  errors), but no real player has entered a dungeon with it live. To test: take a
  character into a 5-man (e.g. Deadmines), confirm the guide appears near the entrance
  facing the arrival point, that its list matches quests the character can actually
  take, that accepting one adds it to the log, and that the empty-list greeting shows
  when nothing qualifies. Worth also checking a multi-entrance dungeon (Dire Maul,
  Maraudon) spawns it at the right door. If a quest is missing or wrongly offered, fix it
  in `dungeon_quest_guide_override` rather than in code.
- **Two stale backups hold the dead DB password in plaintext**:
  `/opt/server-status/check_status.sh.bak-20260912_031957` and `.bak-20260912_032152`
  (plus `~/.my.cnf.bak` and the `backups-weekly/*/configs/` copies). The password no
  longer works, so nothing is exposed - but delete them if you would rather it not be
  on disk. `.bak-20260912_032305` is the better rollback target regardless.
- Alt characters auto-questing and levelling via the playerbots altbot system.
- AdiBags is the chosen combined-bag addon for players (auto-sorts into categories).
- **Pending: first real test-server deployment.** Once a second machine is
  available, run `deployment-kit/deploy.sh` against it (`template` mode, a
  fresh box, not a clone of live player data) and go through it step by
  step rather than unattended - the real SSH path, the actual build, and DB
  init have only been smoke-tested locally, never against a genuine second
  machine. Afterward, diff the target's resulting config files against this
  server's live ones to confirm everything matches except what's supposed
  to differ (DB host, DB password, install paths, hostname).

A deployment kit already exists at `/home/gailin/deployment-kit/` (`deploy.sh`,
see its README), covering both migration/DR (full mode) and handing a clean copy
to a friend (template mode). Map/vmap/mmap/dbc data is copied from this server
rather than re-extracted on the target. It always reads live state (configs,
systemd units, git commits) at run time rather than keeping stale copies, so
there's nothing to "refresh" when this server's tuning changes.
