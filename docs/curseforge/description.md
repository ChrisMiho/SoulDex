![SoulDex](BANNER_IMAGE_URL)

## Every Soul Shard remembers whose soul it holds

Warlocks collect Soul Shards all day. **SoulDex** turns that chore into a collection:
each time a shard lands in your bags, the mob or player it came from is *caught* and
recorded in your dex. Fill it, earn points and milestones, and compare with other
SoulDex users in your guild.

Made for **World of Warcraft: Forever**.

---

### ◆ Three collections

- **Mobs**: every creature you've drained, grouped by zone and dungeon. Elites, rares
  and bosses show in their usual colours.
- **Players**: every player you've sharded, grouped by class.
- **Raids**: a fixed list of every creature in every vanilla raid (Zul'Gurub, Molten
  Core, Onyxia's Lair, Blackwing Lair, Ruins and Temple of Ahn'Qiraj, Naxxramas).
  Uncaught souls show as `? ? ?` and bosses are marked before you catch them. This is
  the one collection you can finish.

Click any soul for its details: level and type, a short flavour line, how many times
you caught it, and when and where you caught it first.

### ◆ Your shards remember

Hover a Soul Shard in your bags and the tooltip tells you whose soul it holds, and
where and when you took it. The soul follows its shard through your bags, the bank and
relogs.

### ◆ A small game on top

- A **popup and a sound** when you catch a soul for the first time. Repeat catches stay quiet.
- **Points** for each first catch: 1 for a normal mob, 5 for an elite, 10 for a rare
  or a player, 25 for a boss.
- **Milestones** for unique mobs, player souls and each raid completed.
- A **Me** tab with your score, souls taken, most-caught mob, top zone and your rank
  among friends.

### ◆ Friends

SoulDex users in your party, raid and guild appear on a leaderboard on their own. Add
anyone else with `/souldex add <name>`. Browse a friend's dex, read-only: what they
have and you don't is highlighted.

Guild announcements are **for big moments only** (from 100 unique mobs, 25 player
souls, and raid completions), never for every catch. They switch off with one tick.

---

### Commands

| Command | What it does |
|---|---|
| `/souldex` or `/dex` | Open or close the window |
| `/souldex options` | Settings (also the gear on the window) |
| `/souldex add <name>` | Add a friend by name |
| `/souldex remove <name>` | Remove a friend |

### Settings

The new-catch popup, the sound and guild announcements each have their own on/off switch.

### How catching works on WoW: Forever

Forever hides the combat log from addons, so SoulDex reads your target when you start
**Drain Soul** (or cast **Shadowburn**) and names the next new shard after it. When the
game hides the target's name, the catch counts as an **Unknown soul** in that zone (no
points, no popup). SoulDex never guesses: a shard it can't match to a cast is left
unnamed rather than recorded under the wrong name. Shards from before you installed the
addon have no soul to show.

Raid creature lists are based on Classic Era data and may differ slightly from Forever.

---

### Feedback

Bug reports and ideas are welcome in the comments. Each file on the Files tab lists
what changed in that version.

Raid creature data (NPC IDs, names, raid and boss flag) comes from
[Questie](https://github.com/Questie/Questie) (GPL-3). Uses AceComm-3.0, CallbackHandler-1.0
and LibStub from Ace3.

*Drain freely. Every soul counts.*
