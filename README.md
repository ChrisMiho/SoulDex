# Soul-Dex

A collection dex for your Soul Shards. A World of Warcraft: Forever addon for
warlocks: every time a Soul Shard lands in your bags, the mob or player it came
from is "caught" and recorded in your dex. Collect them, earn points and
milestones, and compare with other Soul-Dex users.

## Features

- Three collections: **Mobs** (grouped by place), **Players** (grouped by class)
  and **Raids** (a fixed list of every vanilla raid creature, so you can finish it).
- A popup and sound for each new catch, points for first catches, and milestones.
- Hover a Soul Shard in your bags to see whose soul it holds and where it was taken.
- **Friends**: a leaderboard of Soul-Dex users in your party, raid and guild, plus
  anyone you add by name. Browse their dex read-only; what you lack is highlighted.
- Optional guild announcements for big moments only.

## Usage

| Command | What it does |
|---------|--------------|
| `/souldex` (or `/dex`) | Open or close the Soul-Dex window |
| `/souldex options` | Open the settings (also the gear on the window) |
| `/souldex add <name>` | Add a friend by name |
| `/souldex remove <name>` | Remove a friend |

### Settings

- New-catch popup on/off
- New-catch sound on/off
- Guild announcements on/off

## Install

Install from CurseForge with your addon manager, or download the latest zip from
the [GitHub releases](https://github.com/ChrisMiho/SoulDex/releases) and unzip
the `SoulDex` folder into `World of Warcraft\_forever_\Interface\AddOns`. Restart
the game the first time; after that, `/reload` picks up updates.

## How it works

WoW: Forever hides the combat log from addons, so Soul-Dex reads your target
when you start Drain Soul (or cast Shadowburn) and names the next new shard
after it. When the game hides the target's name, the catch is counted as an
**Unknown soul** in that zone (no points, no popup). A shard Soul-Dex can't
match to a capture records nothing, so the dex never holds a wrong name.

Your dex is saved per character. Nothing leaves your game except guild
announcements (if you turn them on) and the small addon messages the Friends
tab exchanges with other Soul-Dex users.

## Bugs and ideas

Open an [issue on GitHub](https://github.com/ChrisMiho/SoulDex/issues). Say
what you did, what you expected and what happened instead, and include any Lua
error text.

## Development

You need Lua 5.1 tooling: `luarocks --lua-version 5.1 install luacheck` and
`luarocks --lua-version 5.1 install busted`. On Windows, run the `.sh` scripts
in Git Bash.

| Task | Command |
|------|---------|
| Lint | `luacheck .` |
| Unit tests | `busted` |
| Build, zip and install into the game | `scripts/build.sh` |
| Build and zip only | `scripts/build.sh --no-install` |

`scripts/build.sh` installs into the standard Windows game folder; set
`WOW_ADDONS_DIR` to install somewhere else. The zip lands in `.release/`.

Behaviour is described in
[the design spec](docs/superpowers/specs/2026-11-10-soul-dex-design.md); code
and spec change together. Code conventions and repo layout are in
[`CLAUDE.md`](CLAUDE.md), which is written for both people and coding agents.
CI runs lint and tests on every push; releases are built from `v*` tags.

## Data

The raid creature lists (NPC IDs, names, raid membership and boss flag) are
generated from [Questie](https://github.com/Questie/Questie) v11.38.0
(`Database/Classic/classicNpcDB.lua`), which is licensed under GPL-3. See
`scripts/gen_raids.lua` and the header of `src/RaidData.lua`. Data is based on
Classic Era and may differ from WoW: Forever.

## Licence

Copyright (C) 2026 ChrisMiho. GNU General Public License v3.0; see `LICENSE`.
The raid data in `src/RaidData.lua` comes from Questie, also GPL-3; see Data above.
