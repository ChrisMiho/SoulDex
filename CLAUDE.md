# Soul-Dex

World of Warcraft: Forever addon (Lua 5.1, Interface 16001), a Pokédex for a
warlock's Soul Shards. It records what dies while a shard is being taken and
fills a dex of creatures. `/souldex` opens the window. Settings and the dex are
saved per character in `SoulDexDB`. Personal output goes to the player's own
chat frame only; the only chat-channel output is guild announcements.

## Spec

`docs/superpowers/specs/2026-11-10-soul-dex-design.md` is the owning
document. A change to behaviour is not done until the spec and the code agree.

## Commands

Run from the repo root. On Windows, `.sh` scripts need Git Bash.

| Task | Command |
|------|---------|
| Lint | `luacheck .` |
| Unit tests | `busted` |
| Build, zip and install into the game | `scripts/build.sh` |
| Build and zip only (no game install) | `scripts/build.sh --no-install` |

In game: `/souldex`, `/souldex options`, `/souldex add <name>`, `/souldex remove <name>`.

Lint and tests must pass before you call work done; CI runs both on every push.
The build output goes to `.release/` (git-ignored). `scripts/build.sh` only
works in a normal checkout: inside a git worktree the packager stops with
"No Git, SVN, or Hg checkout found".

## Layout

| Path | Purpose |
|------|---------|
| `SoulDex.toc` | Load order and SavedVariables. Every new `src/` file must be listed here, above `src\Init.lua` |
| `embeds.xml` | Library includes (LibStub, CallbackHandler, AceComm) |
| `src/Settings.lua` | Pure: setting defaults and `normalise` |
| `src/RaidData.lua` | Generated raid creature lists (Questie, GPL-3); do not hand-edit, run `luajit scripts/gen_raids.lua <path>` |
| `src/Raids.lua` | Pure: raid lookups by NPC id |
| `src/Points.lua` | Pure: points per catch |
| `src/Flavour.lua` | Pure: flavour text templates |
| `src/Dex.lua` | Pure: dex storage, recording, counts |
| `src/Milestones.lua` | Pure: milestone list and checks |
| `src/View.lua` | Pure: row/group data for the tabs |
| `src/Comm.lua` | Pure: encode/decode of friend messages |
| `src/Friends.lua` | Pure: friends store and leaderboard |
| `src/Catch.lua` | Pure: matching deaths to shards |
| `src/Shards.lua` | Pure: bag slot to soul map |
| `src/Toast.lua` | New-catch popup and sound |
| `src/Capture.lua` | Game events: tracks units, deaths, bag scans, records catches |
| `src/Tooltip.lua` | Soul Shard tooltip lines |
| `src/UIFormat.lua` | UI text and colour helpers |
| `src/UIList.lua` | Pooled scrolling list component |
| `src/UI.lua` | Dex window, tabs, panes |
| `src/UIDetail.lua` | Detail pane content |
| `src/Options.lua` | Options panel |
| `src/Net.lua` | Friends network (AceComm), Friends tab |
| `src/Init.lua` | WoW glue: version, `ns.Print`, ADDON_LOADED, `/souldex` |
| `scripts/gen_raids.lua` | Generates `src/RaidData.lua` from the Questie NPC database (not shipped) |
| `spec/` | busted tests, one `<Module>_spec.lua` per module |
| `scripts/` | Developer scripts (not shipped) |
| `docs/` | Design specs and plans (not shipped) |
| `.pkgmeta` | Packager config: library externals, files left out of the package |

## Code rules

- **Every file starts with `local addonName, ns = ...`** (or `local _, ns = ...`).
  Share code through `ns`, never through new globals.
- **Keep pure logic separate from game code.** Pure modules call no WoW API and
  get busted tests; frames, events, timers, chat output and the WoW API stay in
  game-facing files.
- **Test pure modules through `LoadAddonFile`** (from `spec/helper.lua`), which
  loads a file the way the game does.
- **Declare every WoW API you use** in `read_globals` in `.luacheckrc`, and every
  global you create in `globals`.
- **Messages go to the player's own chat frame only** (`ns.Print`), never to a
  chat channel, except guild announcements.
- **Never record a wrong name in the dex.** A shard with no matching death
  records nothing.
- **Libraries only through `.pkgmeta` externals** (pinned to `Release-r1403`)
  and `embeds.xml`; never commit `Libs/` or copy library code into `src/`.
- Tabs for Lua indentation; see `.editorconfig`.
- Newly created files are left out of builds until they are `git add`ed.

## Things only a human can check

Anything that needs the game client. When a task depends on one of these,
finish the parts you can test, then list exactly what the user should try in
game and what they should expect to see. Section 9 of the spec
(`docs/superpowers/specs/2026-11-10-soul-dex-design.md`) is the full list; keep it
up to date.

## Changes and releases

- Add a line under `## [Unreleased]` in `CHANGELOG.md` for each user-facing change.
- Releases are made by pushing a `v*` tag. Do not tag or push unless asked.
