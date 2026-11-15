# SoulDex

World of Warcraft: Forever addon (Lua 5.1, Interface 16001): a collection dex
for a warlock's Soul Shards. It records what dies while a shard is being taken
and fills a dex of creatures. `/souldex` (or `/dex`) opens the window. Settings
and the dex are saved per character in `SoulDexDB`.

## Spec

`docs/superpowers/specs/2026-11-10-souldex-design.md` is the owning
document. A change to behaviour is not done until the spec and the code agree.

## Commands

Run from the repo root. On Windows, `.sh` scripts need Git Bash. On macOS the
build needs a newer bash than the system one: `brew install bash` (the script
finds it by itself).

| Task | Command |
|------|---------|
| Install tools (once) | `luarocks --lua-version 5.1 install luacheck` and `... install busted` |
| Lint | `luacheck .` |
| Unit tests | `busted` |
| One test file | `busted spec/Dex_spec.lua` |
| Build, zip and install into the game | `scripts/build.sh` |
| Build and zip only (no game install) | `scripts/build.sh --no-install` |
| Redraw the rank emblems | `scripts/art/render.sh` (needs Chrome and Python 3 with Pillow) |

Lint and tests must pass before you call work done; CI runs both on every push,
and a Stop hook (`.claude/hooks/check.sh`) runs them when Lua files changed.
The build output goes to `.release/` (git-ignored). `scripts/build.sh` installs into
the standard game folder for Windows or macOS, or into `WOW_ADDONS_DIR` when
set; when no game folder is found it makes the zip and skips the install. The build only works in a normal checkout: inside a git
worktree the packager stops with "No Git, SVN, or Hg checkout found".

## Layout

- **Pure modules** (no WoW API, busted-tested): `Settings`, `Raids`, `Points`, `Ranks`,
  `Rarity`, `Flavour`, `Dex`, `Milestones`, `View`, `Comm`, `Friends`, `Catch`,
  `Shards`, `UIFormat`.
- **Game-facing** (frames, events, chat): `Capture` (secret-value guards,
  spellcasts, bag scans), `Tooltip`, `Toast`, `UI`, `UIList`, `UIDetail`,
  `Options`, `Net` (AceComm), `Init` (version, `ns.Print`, slash command).
- `SoulDex.toc` is the load order: every new `src/` file goes there, above
  `src\Init.lua`.
- `art/` holds the rank emblems, generated from `scripts/art/emblem.html` by
  `scripts/art/render.sh` (needs Chrome and Python 3 with Pillow): never hand-edit.
- `src/RaidData.lua` is generated from Questie (GPL-3): never hand-edit, run
  `luajit scripts/gen_raids.lua <path to classicNpcDB.lua>`.
- Not shipped (`.pkgmeta` `ignore`): `spec/`, `scripts/`, `docs/`, `CLAUDE.md`;
  dotfiles are left out by the packager. `scripts/probe/` is a throwaway
  diagnostic addon, not part of SoulDex.

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
- **Never record a wrong name in the dex.** A shard with no matching capture
  records nothing.
- **This client blocks the combat log and may return secret values:** never
  register COMBAT_LOG_EVENT_UNFILTERED; check every API value with
  issecretvalue before use (`ns.Capture.readable`/`plainString`/`plainNumber`).
- **Libraries only through `.pkgmeta` externals** (pinned to `Release-r1403`)
  and `embeds.xml`; never commit `Libs/` or copy library code into `src/`.
- A new rank needs its emblem (`art/rank<N>.tga`); `spec/Art_spec.lua` checks.
- Tabs for Lua indentation; see `.editorconfig`.
- Newly created files are left out of builds until they are `git add`ed.
- Don't use Pokémon names or art anywhere players see it (CurseForge rules on
  trademarks); "dex" alone is fine.

## Things only a human can check

Anything that needs the game client. When a task depends on one of these,
finish the parts you can test, then list exactly what the user should try in
game and what they should expect to see. Section 9 of the spec is the full
list; keep it up to date.

## Changes and releases

- Add a line under `## [Unreleased]` in `CHANGELOG.md` for each user-facing change.
- Releases are made by pushing a `v*` tag. The `/release` skill then saves the
  published zip to `releases/` (git-ignored); the release workflow uploads the same zip to CurseForge. Do not tag or push unless asked;
  the steps are in the `/release` skill (`.claude/skills/release/SKILL.md`).
- Personal details stay out of the repo: commit with the GitHub no-reply
  address, and write no local paths or emails into docs.
