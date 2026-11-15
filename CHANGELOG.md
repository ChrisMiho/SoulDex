# Changelog

All notable changes to this addon are listed here.
Versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.3.0] - 2026-11-15

- Warlock ranks, from Initiate to Lord of Souls, each with its own emblem; ranking up gets its own popup, and from Reaper on your guild hears about it.
- Mastery stars and repeat claims: claiming the same mob again can earn stars and points, and bosses, rares and players score again too. Your existing dex counts.
- A new window: a rebuilt Me tab with records, trophy-card soul details, grouped milestones with progress bars, and a livelier popup.
- Souls drained in dungeons now get their real names (SoulDex quietly whispers you to read them); bosses killed mid-fight still show as Unknown.
- WoW: Forever's own raids, The Barrow Deeps and Hyjal Summit, are listed with their rosters to come.
- New option, off by default: claim chatter in chat. Souls are now "claimed" rather than "caught".

## [1.2.4] - 2026-11-14

- The addon is now called SoulDex everywhere: the window, options, chat lines, guild announcements and the addon list.

## [1.2.3] - 2026-11-14

- SoulDex is now licensed under the GNU GPL v3 (it was MIT), matching the Questie raid data it ships.
- The in-game addon list now describes SoulDex as "A collection dex for your Soul Shards".

## [1.2.2] - 2026-11-14

- The first new soul of a session no longer lags: the popup and sound are loaded at login, or when you switch them on.

## [1.2.1] - 2026-11-14

- Guild announcements earned during a boss fight are no longer lost: they wait and go out when the fight ends.

## [1.2.0] - 2026-11-14

- The new-catch popup shows your soul count: "Soul #42".
- `/dex` works as a shortcut for `/souldex`.
- A chat line after login shows SoulDex is loaded, with its version.
- Fixed: a brief lag on the first popup, popup colours that didn't match the window, and a few smaller issues.

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
- Friends tab: a leaderboard of SoulDex users in your party, raid and guild plus people added with `/souldex add <name>`; browse a friend's dex read-only.
- `/souldex options` (or the gear) toggles the popup, the sound and guild announcements.
- Fixed: nothing was recorded on WoW: Forever (the combat log is blocked for addons). Catches now come from your Drain Soul / Shadowburn casts and shards are tracked by item, so a soul follows its shard anywhere. A target whose name the game hides is counted as an "Unknown soul" in that zone.
- Fixed: the new-catch popup errored on WoW: Forever (`GetItemIcon` no longer exists).
- Fixed: two-part character names (WoW: Forever's "Forgot Shards") — you no longer show up as your own friend, and player catches keep the full name.
