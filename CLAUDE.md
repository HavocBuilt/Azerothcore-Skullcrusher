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
before promising that any given table can be reloaded live.

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

**Where the DBCs actually are.** `worldserver.conf` says `DataDir = "./data"`, but the
live DBC files worldserver reads are at **`/home/gailin/azeroth-server/bin/dbc/`**
(`azeroth-server/data/dbc/` does not exist). Useful when a value isn't in MySQL at all —
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
