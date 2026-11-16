# Dev tools for the restricted API: PRD

Status: proposed, 2026-11-15. For an agent working on the machine that runs the
game. Read `CLAUDE.md` first: its code rules (pure vs game-facing modules,
`issecretvalue` on every value, `.luacheckrc` globals, tabs, `ns.Print` only)
apply to everything here.

## Why

The Forever client hides values from addons ("secret values") depending on the
situation: open world, combat, dungeon, boss encounter. We learn what it hides
with the in-game probe (`scripts/probe/SoulDexProbe/`, `/sdprobe`), but today:

- the probe is copied into the AddOns folder by hand;
- its log (`SoulDexProbeLog`) is read raw and turned into tables by hand
  (section 7a of `2026-11-15-soul-name-whisper-design.md` was made that way);
- the busted tests don't use what the probe found: every spec writes its own
  `issecretvalue` stub (`spec/Capture_spec.lua:84`, `spec/Net_spec.lua:377`, …),
  so the tests can drift away from the real client without anything failing;
- when SoulDex itself misbehaves in game ("nothing fires"), there is no record of
  what it saw or decided. All we have is what the player remembers.

Goal: each probe run becomes test data without manual steps, and a broken
session leaves a record we can read.

## Scope

Four pieces. Build them in this order; each one stands on its own.

| # | Piece | Ships to players? |
|---|---|---|
| A | Probe install step | no |
| B | Probe log reader | no |
| C | Secrecy matrix: the probe records it, the tests use it | no |
| D | SoulDex debug log (`/dex debug`) | yes (opt-in) |

Out of scope: a lint check for unguarded API reads (maybe later), any change to
how catching works, publishing anything.

---

## A. Probe install step

**What:** a way to install the probe the same way `scripts/build.sh` installs
SoulDex.

- Add `scripts/probe/install.sh`. It copies `scripts/probe/SoulDexProbe/` into
  the AddOns folder and replaces any copy already there.
- Find the AddOns folder the same way `scripts/build.sh` does (lines 14–26 and
  103–120): `WOW_ADDONS_DIR` if set, else the standard Forever folder for
  macOS / Windows (Git Bash). Use the same "refuse if it is a link" guard. Pull
  the shared folder logic into a small sourced file
  (e.g. `scripts/lib/addons_dir.sh`) rather than copying it.
- `--remove` deletes the installed probe, so it doesn't stay loaded by mistake.
- Print what it did and remind the player to `/reload`.

**Done when:** running it on the game machine puts `SoulDexProbe` in AddOns,
`/sdprobe` works after `/reload`, and `--remove` takes it out. `build.sh`
behaves exactly as before.

## B. Probe log reader

**What:** a script that turns the probe's SavedVariables file into readable
output.

- `scripts/probe/read_log.lua`, run with `luajit` (like `scripts/gen_raids.lua`).
  Argument: path to the SavedVariables file, i.e.
  `WTF/Account/<ACCOUNT>/SavedVariables/SoulDexProbe.lua` (account-wide) or the
  per-character one under `<Realm>/<Character>/` if the TOC changes to that.
  No argument: look in the standard WTF folder next to the AddOns folder from A
  and list the candidates.
- Load the file in a sandbox (`setfenv` with an empty table; it is just
  `SoulDexProbeLog = { ... }`), never with access to `os`/`io`.
- Output modes:
  - default: the log lines, grouped by session (`---- probe loaded ----`
    separates them), with long `unit=… exists=… guid=…` lines broken into
    `key = value` rows;
  - `--matrix`: the secrecy matrix from C as a Markdown table (API ×
    situation, cells `readable` / `secret` / `error` / `missing`), ready to
    paste into a spec;
  - `--grep <pattern>`: only matching lines.
- Logic that parses lines goes in a pure module (e.g.
  `scripts/probe/ProbeLog.lua`) with a busted spec under `spec/`, using a small
  fixture file taken from a real log. The script is a thin wrapper around it.
- **Privacy:** the probe log can contain character names and GUIDs. The reader
  prints them locally; never commit a raw log. Fixtures must be scrubbed (fake
  names, fake GUIDs).

**Done when:** pointed at a real probe file it prints readable sessions, and
`--matrix` prints a table matching what the log says.

## C. Secrecy matrix: the probe records it, the tests use it

**What:** the probe records automatically which API reads are readable or secret
in each situation. A generator turns that into a Lua table, and a shared spec
helper builds the API stand-ins from that table.

### C1. Probe side (`scripts/probe/SoulDexProbe/Probe.lua`)

- A declared list of reads, `READS = { {id = "UnitName.target", fn = …}, … }`,
  covering at least every API SoulDex's game-facing files call on a unit, the
  chat, spellcasts and bags. Start from the reads `unitLine`, `sceneLine`,
  `restrictionLine` and section 7a already cover, then grep `src/` for the
  rest.
- A "situation" made of: `instanceType` (from `GetInstanceInfo`: none / party /
  raid / …), `inCombat` (`InCombatLockdown`), `encounter`
  (`IsEncounterInProgress`), `chatLock` (`InChatMessagingLockdown`), and
  whether there is a target (alive / dead / none).
- Take a snapshot of every read when the situation changes
  (`PLAYER_REGEN_DISABLED/ENABLED`, `ENCOUNTER_START/END`,
  `PLAYER_ENTERING_WORLD`, `ADDON_RESTRICTION_STATE_CHANGED`,
  `PLAYER_TARGET_CHANGED` at most once per situation), and on
  `/sdprobe matrix`.
- Store it in a separate table, `SoulDexProbeMatrix[situationKey][readId] =
  "readable" | "secret" | "error" | "missing"`, plus the game build
  (`GetBuildInfo`) and the date. Record classes only, never the values
  themselves (no names or GUIDs in this table). Merge across sessions; if one
  cell gets different results, keep both (`"readable|secret"`) so the
  difference shows up.
- Add the table to the probe's `## SavedVariables`.

### C2. Generator

- `luajit scripts/probe/gen_secrecy.lua <SavedVariables file>` writes
  `spec/fixtures/secrecy.lua`: a `return { build = …, date = …, situations = {
  … } }` table, sorted, with a header saying it is generated and must not be
  hand-edited (same style as `src/RaidData.lua`).
- The fixture goes in `spec/`, which already isn't shipped (`.pkgmeta` ignore).

### C3. Spec helper

- Add a function to `spec/helper.lua` (or a new `spec/secrecy_helper.lua`
  loaded from it), e.g. `Secrecy.apply(world, situation)`. It installs
  `_G.issecretvalue` and wraps the stub API functions a spec has already set
  up, so a read marked `secret` in that situation returns a secret sentinel.
- Situations are named the way the fixture names them, plus simple aliases:
  `"openWorld"`, `"dungeonOutOfCombat"`, `"dungeonPull"`, `"bossEncounter"`.
- Move the existing hand-written secret stubs in `Capture_spec.lua` and
  `Net_spec.lua` onto the helper where the test is about a real situation. Keep
  hand-written stubs where a test is about one specific value on purpose.
- Add one spec per situation that runs a normal Drain Soul catch through
  `Capture` and checks the result matches the spec (named in the open world,
  asked by whisper in a dungeon, Unknown soul during an encounter).

**Done when:** `busted` and `luacheck .` pass. If you edit the fixture to mark
`UnitName.target` readable during an encounter, at least one test fails.
Regenerating from a new probe run is one command.

## D. SoulDex debug log (`/dex debug`)

**What:** an opt-in, bounded log inside SoulDex of what the capture code saw and
decided, so a broken session ("nothing fires") can be read afterwards.

- **Off by default.** `/dex debug on|off` toggles it, `/dex debug` prints the
  last 20 lines to the player's chat frame (`ns.Print`), `/dex debug clear`
  empties it. Add these to the `/dex` help text. Not in the options panel.
- Pure module `src/DebugLog.lua` (busted-tested): a ring buffer of at most
  500 lines, stored in `SoulDexDB.debugLog = { on = bool, lines = { … } }`.
  Each line gets a timestamp and a short event tag. Time comes from the caller
  (the pure module calls no WoW API).
- Game-facing hooks (in `Capture`, `Whisper` handling, `Net`, `Init`): one
  line per decision, e.g. `load v1.2.0`, `events registered`,
  `SENT 1120 target=<secret>`, `channel start`, `channel stop`,
  `bag scan +1 shard guid=ok`, `capture matched → Kobold Miner`,
  `name secret → ask whisper token=…`, `reply ok`, `lockdown, no ask → Unknown`,
  `shard without capture → nothing recorded`. **Never write a secret value**:
  write `<secret>`. Only `plainString`/`plainNumber` values go into the log.
- When it is off, logging must cost nothing more than one boolean check.
- Load (`ADDON_LOADED`/`PLAYER_LOGIN`) and event registration are logged even
  on the first session after turning it on. Those are the lines that answer
  "is anything firing at all?".
- Lua errors caught by SoulDex's own `pcall`s are logged with their message.
- Spec: add a short subsection to `2026-11-10-souldex-design.md` (section 6,
  game layer), a line under section 9 (in-game checks), and a
  `CHANGELOG.md` line under `## [Unreleased]`.
- Declare any new globals/APIs in `.luacheckrc`; add `src/DebugLog.lua` to
  `SoulDex.toc` above `src\Init.lua`; `git add` it (builds skip untracked files).

**Done when:** busted covers the ring buffer (bounding, on/off, clear,
secret values written as `<secret>`); in game, `/dex debug on` → `/reload` →
Drain Soul → `/dex debug` shows the load, the cast, the bag scan and the
outcome.

---

## In-game checks (for the player)

1. `scripts/probe/install.sh`, `/reload`: chat shows `SoulDexProbe ----
   probe loaded ----`. `--remove`, `/reload`: it's gone.
2. With the probe loaded: walk around, pull a mob, enter a dungeon, pull, and
   (if possible) a boss. Run `/sdprobe matrix` once in each situation, then
   `/reload`. Then run `read_log.lua --matrix` on the SavedVariables file: one
   column per situation, matching section 7a where they overlap.
3. `/dex debug on`, `/reload`, Drain Soul a mob: `/dex debug` lists the load,
   the cast, the bag scan and the outcome. `/dex debug off`: no new lines after
   the next catch.

## Notes for the implementing agent

- Work on a branch off `experimental`; don't push to `main`, don't tag.
- `luacheck .` and `busted` must pass before calling any piece done (the Stop
  hook runs them too). `scripts/probe/` is excluded from luacheck; new pure
  modules under `scripts/probe/` that have specs should be linted. Narrow the
  exclude to `scripts/probe/SoulDexProbe/`.
- Keep the probe a throwaway: it is never listed in `SoulDex.toc` and never
  shipped. D is the only piece players get.
