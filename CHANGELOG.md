# Changelog

All notable changes to this addon are listed here.
Versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.1.0] - 2026-11-11

- Friends: hover any row for a × that removes that person, including guild and group members you never added; a new "Clean up" button (with a confirmation) removes everyone you didn't add who isn't in your guild or group.
- Friends: browsing someone who doesn't answer asks again after 60 s and gives up after 90 s, with a chat line each time.
- Beasts of the common families (wolves, spiders, boars, cats and more) get their own flavour lines.
- Fixed: `/souldex add`, `/souldex remove` and the × didn't work with WoW: Forever's two-part names.
- Fixed: a shard from the mailbox, a trade or a vendor, or one arriving alongside another new shard, could be named after the mob you were draining. Such shards now stay unnamed.
- Fixed: a hidden target name reported by the cast no longer lets the current target's name through (it is an Unknown soul).
- Fixed: the popup always said "#1 here"; it now shows how many different mobs you have in that zone.
- Fixed: raid creature detail panes showed no rarity, level or type.
- Fixed: the player detail pane spelled the class in English on other-language clients.
- Fixed: a late dex from someone you browsed earlier no longer opens over the person you're browsing now.
- Fixed: incoming friend messages are fully checked (version, shape, no negative or huge scores) before anything is done with them.
- Fixed: damaged saved data no longer breaks the window, and an error while recording one catch can't lose the others' shard souls.
- Fixed: a one-word player named like the first half of your name was ignored as if they were you.

## [1.0.0] - 2026-11-11

- Me tab: your score, unique mobs, players, raids, souls taken, zones, most-caught mob, top zone and your rank among friends; the Friends tab keeps your row only as a ranked marker, hidden until someone else is listed.
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
