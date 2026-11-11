# Soul-Dex

A Pokédex for your Soul Shards. A World of Warcraft: Forever addon for warlocks:
every time a Soul Shard lands in your bags, the mob or player it came from is
"caught" and recorded in your dex. Collect them, earn points and milestones,
and compare with other Soul-Dex users.

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
| `/souldex` | Open or close the Soul-Dex window |
| `/souldex options` | Open the settings (also the gear on the window) |
| `/souldex add <name>` | Add a friend by name |
| `/souldex remove <name>` | Remove a friend |

### Settings

- New-catch popup on/off
- New-catch sound on/off
- Guild announcements on/off

## Install

Download the latest zip from the GitHub releases page and unzip the `SoulDex`
folder into `World of Warcraft\_forever_\Interface\AddOns`, then `/reload`.

To build from source, run `scripts/build.sh` in Git Bash.

## Data

The raid creature lists (NPC IDs, names, raid membership and boss flag) are
generated from [Questie](https://github.com/Questie/Questie) v11.38.0
(`Database/Classic/classicNpcDB.lua`), which is licensed under GPL-3. See
`scripts/gen_raids.lua` and the header of `src/RaidData.lua`. Data is based on
Classic Era and may differ from WoW: Forever.

WoW: Forever hides the combat log from addons, so Soul-Dex reads your target
when you start Drain Soul (or cast Shadowburn) and names the next new shard
after it. When the game hides the target's name, the catch is counted as an
**Unknown soul** in that zone (no points, no popup).

## Licence

MIT. See `LICENSE`. The Questie-derived raid data in `src/RaidData.lua` comes
from a GPL-3 project; see Data above.
