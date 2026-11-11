# Changelog

All notable changes to this addon are listed here.
Versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

- Catch the soul behind every Soul Shard: Drain Soul and Shadowburn kills are recorded as mobs, players or raid creatures in your dex.
- Mobs, Players, Raids and Milestones tabs in a small purple window (`/souldex`), with detail panes, flavour text and a remembered position and tab.
- Raids tab with a fixed list of every vanilla raid creature (Zul'Gurub, Molten Core, Onyxia, Blackwing Lair, AQ20, AQ40, Naxxramas).
- New-catch popup and sound, points for first catches, and milestones with optional guild announcements.
- Soul Shard tooltips show whose soul it is and where it was taken, following the shard between bag slots.
- Friends tab: a leaderboard of Soul-Dex users in your party, raid and guild plus people added with `/souldex add <name>`; browse a friend's dex read-only.
- `/souldex options` (or the gear) toggles the popup, the sound and guild announcements.
- Fixed: nothing was recorded on WoW: Forever (the combat log is blocked for addons). Catches now come from your Drain Soul / Shadowburn casts and shards are tracked by item, so a soul follows its shard anywhere. A target whose name the game hides is counted as an "Unknown soul" in that zone.
- Fixed: the new-catch popup errored on WoW: Forever (`GetItemIcon` no longer exists).
- Fixed: two-part character names (WoW: Forever's "Forgot Shards") — you no longer show up as your own friend, and player catches keep the full name.
