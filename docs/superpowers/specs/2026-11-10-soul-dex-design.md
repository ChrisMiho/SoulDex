# Soul-Dex — design

Date: 2026-11-10
Status: awaiting user approval

## 1. What it is and why

Soul-Dex is a World of Warcraft: Forever addon for warlocks. It turns
collecting Soul Shards into a collection minigame, like a Pokédex: every time
a shard lands in your bags, the mob or player it came from is "caught" and
recorded in the dex.

Warlocks collect shards all the time anyway. Soul-Dex gives that chore a
collector's goal, a record of where your souls came from, and something to
compare with other warlocks.

The user chose these things (marked **[user]**). Calls made while writing
this document are marked **[call]**, and the user should check them.

## 2. Goals, non-goals, anti-goals

### Goals

- Every shard you collect records its source: a mob or a player. **[user]**
- Three collections, each with its own tab: **Mobs** (open world and
  dungeons, grouped by place), **Players** (grouped by class), and **Raids**
  (a fixed, completable list of every raid mob). **[user]**
- Only the Raids collection is completable. The Mobs and Players collections
  are open-ended: they only show what you've caught, never `???` blanks. **[user]**
  The user decided this because a complete list of every open-world mob is
  impossible to finish and the display gets swamped with blanks.
- The shard in your bag gets extra tooltip lines saying whose soul it is. **[user]**
- A minigame layer: a popup and sound for new catches, points, milestones,
  and guild announcements of big moments. **[user]**
- Social: see other Soul-Dex users in your party, raid or guild, plus anyone
  you add by name. View their score and browse their dex. **[user]**

### Non-goals

- No master list of open-world mobs, and no "X / Y" for zones. **[user]**
- No 3D model portraits. **[user]** (left out when choosing what an entry shows)
- No change to the shard item, its icon, or how bags look. Tooltip lines only. **[user]**
- No content past vanilla for now. Raid data starts from classic vanilla
  (MC, Onyxia, BWL, ZG, AQ20, AQ40, Naxxramas). WoW: Forever plans new content;
  the raid list must be easy to extend later. **[user]**
- No points for repeat catches. **[user]**
- No minimap button. **[call]** Opened with `/souldex`.
- No other WoW clients (Retail, other Classic versions). **[call]**

### Anti-goals (would be a failure even if it works)

- **A busy UI.** The user turned down three layouts for being "over
  complicated", "dead space" and "too much". The window must be small and dense.
  Progress bars were tried twice and dropped.
- **Lists you can never finish** outside raids.
- **Noise you can't turn off.** Popup, sound and guild announcements each have
  their own off switch. **[user]**
- **Chat spam.** Guild announcements are for big moments only, never every catch.

## 3. Platform and constraints

- WoW: Forever, `## Interface: 16001`, Lua 5.1. **[user]**
- Same project setup as the user's other addons (FeelingPeckish,
  DeathRollForever in `C:\Coding\`): `src/` modules sharing code through `ns`,
  pure logic kept apart from WoW glue and tested with busted via
  `LoadAddonFile`, `luacheck` with every WoW API declared, `scripts/build.sh`,
  `.pkgmeta`, a `CHANGELOG.md`, and a `CLAUDE.md` like theirs. **[call]**
- Libraries: AceComm-3.0 (and its dependencies) via `.pkgmeta` externals pinned
  to an Ace3 tag, as DeathRollForever does, for chunked addon messages. Nothing
  else. **[call]**
- Name in game: **Soul-Dex**. Slash command: **`/souldex`**. **[user]**
  The folder, `.toc` and code name can stay `SoulShardPokeDox` or become
  `SoulDex`; that's the builder's choice.
- The project folder is not a git repository yet; the builder sets one up
  like the sibling addons.

## 4. Catching

### 4.1 What counts as a catch

A catch happens when a Soul Shard (item 6265) **appears in your bags**, and
the addon can tell which recent death it came from. No shard, no catch: if
your bags are full and the shard is lost, nothing is recorded. **[call]**
"The shard is the catch" was the user's starting idea.

Shards come from Drain Soul (the target dies while you're channelling it)
and, in vanilla, from Shadowburn (the target dies within 5 s). Both count. **[call]**
Mobs only give shards if they give XP or honour, so the game already filters
out grey mobs.

### 4.2 Linking a shard to its source

The builder decides how to do this. The design needs:

- The source's details are captured **while it's alive and targetable**
  (target, mouseover, or nameplate), keyed by GUID, because a corpse can't
  be queried for some of them. Needed: name, level, classification
  (normal/elite/rare/rare elite/world boss), creature type and family. For
  players: name, realm, level, race, class, guild.
- When a shard appears, it is matched to the most recent death in the last
  few seconds of a unit that had your Drain Soul or Shadowburn on it.
- Recorded with the catch: date and time, your level, the zone (and subzone
  if known), and **your** map coordinates at that moment (the source's own
  position isn't available). **[call]**
- If no match is found, the shard gets no name and no catch is recorded.
  This must never produce a wrong name.

### 4.3 Identity

- **Mobs:** one entry per mob **name** **[user: "each unique mob"]**, filed
  under each place you've caught it. The same name caught in two zones shows
  in both zones' lists, but counts once toward the "unique mobs" total. **[call]**
- **Players:** one entry per player (name-realm). **[user]**
- **Raid mobs:** matched by NPC ID (taken from the GUID) against the raid data
  list, so same-named mobs in different raids stay apart. **[call]**
  Raid mobs are recorded **only** in the Raids collection, not under Mobs. **[call]**

### 4.4 What is recorded

Mob entry: name, level (or level range seen), classification, type, family;
for each place: times caught, first and last date, your level and coordinates
at the first catch. **[user]**

Player entry: name, class, race, guild, level at first and last catch, times
sharded, first and last date, and a list of places (zone and coordinates)
with a count for each. **[user]**

Data is saved **per character** (`SavedVariablesPerCharacter`): each warlock
has its own dex, score and milestones, and Friends shows character names. **[user]**

### 4.5 Counting

- The **unique mobs** total counts every unique mob name across the Mobs
  collection **and** every caught raid mob. Raid catches count toward that
  total, the unique-mob milestones, and the Friends summary, but are only
  *listed* in the Raids tab. **[user]** A raid mob whose name also appears in
  the open world counts once. **[call]**

## 5. The window

The look was settled through mockups; the final versions are in
`.superpowers/brainstorm/*/content/details-v3.html` and
`raids-shard-popup.html`.

### 5.1 Overall

- Small, dense window (around 340 px wide in the mockups), dark purple
  warlock palette, movable, position saved, closes with Escape.
- Title bar: "Soul-Dex · <tab>", plus the total for that tab and the score.
- Tabs along the bottom: **Mobs · Players · Raids · Milestones · Friends**.
- Each collection tab has the same two columns: a **compact list on the left**
  (no bars) and a **list of names on the right**, each name with `×count`.

### 5.2 Mobs tab

- Left: places where you've caught something, under small headers:
  **Eastern Kingdoms**, **Kalimdor**, **Dungeons**. Each place shows its
  count of unique mobs on the right. Places with nothing aren't shown.
- Right: the mobs caught in the selected place. Elites, rares and bosses get
  their usual colours and markers.

### 5.3 Players tab

- Left: the classes, in class colours, each with a count of unique players.
- Right: the players of that class you've sharded, with `×count`.

### 5.4 Raids tab

- Left: every raid, always listed, with `caught / total`, or a ✓ when finished.
- Right: **every** mob in the raid. Uncaught ones show as `? ? ?`. Bosses are
  marked ☠ even before they're caught, so you know what's left.
- Raid data is a generated Lua data file built from a public vanilla
  database: NPC ID, name, raid, and whether it's a boss. It should cover every
  mob that can give a shard (gives XP or honour), so 100% is actually
  reachable. Which mobs to leave out (non-killable, scripted or summoned adds)
  is the builder's call, written down in the data script.
- Baseline: **Classic Era (1.15) data**. **[user: "start with classic data
  for now"; call on 1.15 over 1.12]** WoW: Forever may differ or add content
  later, so: the data file is the only place raid contents live; it's easy to
  regenerate or hand-edit; and the in-game checks (section 9) include
  confirming that NPC IDs in at least one raid match the real client. If a
  caught raid mob's NPC ID isn't in the data, it is still recorded (under
  its raid) so nothing is lost when the data gets fixed. **[call]**

### 5.5 Detail pane

- Clicking a name **slides a pane in from the right**, covering the names
  list; the left list stays visible. **[user]**
- Closed with a small **`◀ Back`** button in the tab style (dark purple,
  light purple text, brighter on hover) at the top left, or a `✕` at the top
  right. It must be easy to find without standing out. **[user]**
- Mob pane: name, rarity, "Lv 11 Humanoid · Gnoll", the flavour line, then
  caught ×N, first (date and your level), where (coordinates), last, and points.
- Player pane: class-coloured name, "Lv 38 Orc Rogue", `<Guild>`, sharded ×N,
  first and last (date and their level), then each place with coordinates
  and a count.

### 5.6 Milestones tab

Not mocked up. Same style: a compact list of milestones, earned ones bright
with their date, the rest dimmed with how far along you are. Milestones:

- Unique mobs: 10, 50, 100, 250, 500, 1000. **[user: "counts"]**
- Unique players: 1, 10, 25, 50, 100. **[call]**
- Each raid completed, and all raids completed. **[call, follows the raid dex]**

### 5.7 Friends tab

Not mocked up. Same two columns. **[user for what; call for layout]**

- Left: Soul-Dex users found in your **party, raid and guild**, plus anyone
  **added by name** (saved list, with an add box and a remove option). **[user]**
- Each shows score, unique mobs, unique players, and raids completed. Sorted
  by score, as a leaderboard.
- Clicking someone opens **their dex** read-only in the same window, with a
  visible "Viewing <name>" marker and a way back to yours. Entries they have
  and you don't are highlighted. **[user]**
- People added by name are contacted directly when they're online. Offline
  people show their last known summary.
- Not limited to warlocks: anyone running the addon shows up. **[user]**

## 6. Game layer

### 6.1 Points

Points only for a **first** catch. Repeats are counted, never scored. **[user]**

| Catch | Points |
|-------|--------|
| Normal mob | 1 |
| Elite | 5 |
| Rare / rare elite | 10 |
| Boss (world boss classification, or raid boss in the data) | 25 |
| Player | 10 |

Raid trash uses the same table by its classification. **[call on values;
the user agreed to this table as an example]**

### 6.2 New-catch popup and sound

- Catching a mob you already have, in a new place, adds it to that place's
  list quietly: no popup, no points. **[call]** "#N here" in the toast is the
  place's unique count after this catch.
- On a **first** catch only (mob, player or raid entry), a small purple toast
  slides in near the top of the screen for a few seconds: "NEW SOUL CAUGHT!",
  the name, rarity, place, "#N here", and "+N pts". A short sound plays. **[user]**
- The popup and the sound each have their own on/off setting. **[user]**

### 6.3 Shard tooltip

- Hovering a Soul Shard in your bags adds two lines to the normal tooltip:
  "Soul of <name>" (in rarity or class colour) and "<zone> · <date>".
  Nothing else changes. **[user]**
- In vanilla, shards don't stack, so each bag slot holds one shard. The addon
  keeps a slot → soul map and updates it when bags change: a shard leaving
  one slot and appearing in another counts as a move; a used or deleted shard
  is dropped from the map.
- When moves can't be told apart (bag sorting, several shards moving at
  once), keep the set of souls but accept that names may swap between
  shards. **[call]** Showing a name on the wrong shard is acceptable here; a
  wrong name in the dex is not.
- Shards from before the addon was installed get no extra lines.

### 6.4 Guild announcements

- **On by default** for big moments only: milestones and raid completions. **[user]**
  New raid bosses are not announced. **[call]** The small milestones (10 mobs,
  1 and 10 players) are not announced; announcing starts at 100 unique mobs
  and 25 unique players. **[call]**
- One switch turns them off. Only sent when you're in a guild.

### 6.5 Flavour text

Each mob gets one silly line built from templates using its type, family,
zone and name, e.g. "A Wolf of Elwynn. Bites first, howls later." **[user]**
The choice of line is fixed per mob (seeded from its name), so it never
changes. Templates cover every creature type, with family-specific lines
where they fit. The wording is the builder's call. Players get no flavour
text. **[call]**

## 7. Settings

`/souldex` opens the window. `/souldex options` (or a small gear in the
window; the builder chooses) opens settings:

- New-catch popup on/off
- New-catch sound on/off
- Guild announcements on/off

All saved.

## 8. Left to the builder

- How death, Drain Soul, Shadowburn and shard appearance are tracked and
  matched (4.2), within the rule "never a wrong name in the dex".
- The addon message protocol, throttling and data sizes for Friends.
- The raid data generation script and source.
- The exact template wording and layout details of Milestones and Friends,
  within the style of the mockups.
- Which zones count as "Dungeons" (instance type party) and how continents
  are found.

## 9. What only the user can check in game

- Drain Soul a mob to death: a shard appears, the popup shows (first time),
  and the mob is listed under the right place.
- Hover that shard: "Soul of <mob>" appears. Move it to another slot: the
  name follows.
- Shard a player in PvP: they appear under their class with their details.
- Kill a raid mob with Drain Soul: it fills its `? ? ?` slot in the Raids tab.
- In one raid, confirm the NPC IDs in the data match what the client reports
  (WoW: Forever may differ from Classic Era).
- Two people with the addon in a party or guild see each other in Friends and
  can browse each other's dex.
- Each setting switch silences what it says.
