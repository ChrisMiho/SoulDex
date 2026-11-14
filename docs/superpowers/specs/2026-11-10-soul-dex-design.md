# Soul-Dex — design

Date: 2026-11-10
Status: approved and built (feat/soul-dex). Deliberate differences from the first draft are marked "(changed during build: ...)".

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
- Name in game: **Soul-Dex**. Slash command: **`/souldex`**, with **`/dex`**
  as a short form that works for every subcommand (`/sd` is left alone: too
  likely to clash with another addon). **[user]**
  The folder, `.toc` and code name can stay `SoulShardPokeDox` or become
  `SoulDex`; that's the builder's choice. (Built as `SoulDex`: `SoulDex.toc`,
  `package-as: SoulDex`, `SoulDexDB`.)

## 4. Catching

### 4.1 What counts as a catch

A catch happens when a Soul Shard (item 6265) **appears in your bags**, and
the addon can tell which recent death it came from. No shard, no catch: if
your bags are full and the shard is lost, nothing is recorded. **[call]**
"The shard is the catch" was the user's starting idea.

Shards come from Drain Soul (the target dies while you're channelling it)
and, in vanilla, from Shadowburn (the target dies within 5 s). Both count. **[call]**
(changed during build: WoW: Forever blocks the combat log for addons, so a
Shadowburn catch is a shard that appears within 5 s + 3 s of a successful
Shadowburn cast, named after the target it was cast at; untested in game.)
Mobs only give shards if they give XP or honour, so the game already filters
out grey mobs.

### 4.2 Linking a shard to its source

The builder decides how to do this. The design needs:

(changed during build: WoW: Forever blocks the combat log for addons -
`CombatLogGetCurrentEventInfo` is missing and registering
`COMBAT_LOG_EVENT_UNFILTERED` is refused - and may return "secret" values. No
death detection is used; the capture window below replaces the death queue.)

- The source's details are read from your **target** when you cast:
  at `UNIT_SPELLCAST_SENT` for Drain Soul or Shadowburn (it is alive then),
  or at `UNIT_SPELLCAST_CHANNEL_START` if no matching SENT was seen. Needed:
  name, level, classification (normal/elite/rare/rare elite/world boss),
  creature type and family. For players: name, realm, level, race, class,
  guild. Every value is checked with `issecretvalue` first; a secret field is
  simply left out. If SENT reports a target name that differs from your
  target's name (a mouseover macro), the name is not trusted (Unknown soul).
  A secret SENT target name can't be compared, so it is not trusted either
  (Unknown soul). When the channel's cast id doesn't match the SENT's (other,
  nil or secret), the target is read at channel start and still cross-checked
  against a SENT of the same spell from under 1 s before; with no such SENT
  the target is trusted (a channel starts on your target by default).
- **Capture window.** A Drain Soul channel start opens a capture for that
  target. A **new shard** that appears while the channel runs, or within 3 s
  after it stops, belongs to that target. A capture lives at most 20 s. A
  successful Shadowburn opens a capture for 5 s + 3 s. An unreadable channel
  start clears the capture (it may be a new channel on an unknown target);
  any other unreadable spell event ends it 3 s later.
- One capture names **one** shard (one channel kills one target); further new
  shards in the same window are soulless. If two unused captures on different
  targets are live at once (a new Drain Soul within 3 s of the last one
  ending), neither names a shard. Two new shards in the same bag scan can't be
  told apart: neither is named, and the capture is spent. A new shard stored
  as soulless by a quiet scan (below) also spends the capture, so it can't
  name a later shard from a trade or the mailbox instead.
- **Unknown soul [user].** When the target's name is hidden (secret, empty,
  or "Unknown"), or there is no target name at all (a focus or mouseover
  macro), the catch is recorded as an Unknown soul in that zone (see 4.4).
  Players whose name is hidden go there too.
- Recorded with the catch: date and time, your level, the zone (and subzone
  if known), and **your** map coordinates at that moment (the source's own
  position isn't available). **[call]**
- If no match is found, the shard gets no name and no catch is recorded.
  This must never produce a wrong name.
- A "new shard" is a Soul Shard whose **item GUID** has never been seen.
  (changed during build: shards are tracked by item GUID, not bag slot, so
  moves, bag sorting and banking can't confuse them; the earlier slot map
  `shardSlots` is discarded.) Bags 0 to the last equipped bag are scanned on
  `BAG_UPDATE_DELAYED`, `PLAYER_REGEN_ENABLED` and after each of your spell
  events. While something is on the cursor or the bank, mailbox, trade or
  vendor window is open, new GUIDs are stored as soulless, never named. The
  shard map is saved after each shard, and an error while recording one catch
  leaves its shard soulless without losing the others. The same applies while any bag slot
  can't be read (secret item ID, or a shard with a secret or missing GUID),
  in this scan or the one before: an old shard turning readable must never
  look new. Only the login scan forgets long-unseen shards.
- Shards that were already in the bags when the addon started, or that can't
  be matched, are remembered as "seen, no soul" (soulless), so they never get
  a name later. Shards that leave the bags are kept (bank, mailbox); a login
  baseline forgets shards not seen for 30 days.
- Login baseline: the first bag scan runs about 1 s after login and records
  every shard then in the bags as soulless. A shard obtained in that first
  second is part of the baseline, not a catch. (changed during build: avoids
  naming old shards on login.)

### 4.3 Identity

- **Mobs:** one entry per mob **name** **[user: "each unique mob"]**, filed
  under each place you've caught it. The same name caught in two zones shows
  in both zones' lists, but counts once toward the "unique mobs" total. **[call]**
- **Players:** one entry per player (name-realm). **[user]** (changed during build: WoW: Forever
  splits character names in two — `UnitName` returns "Forgot", "Shards" for "Forgot Shards" — so
  the two parts are joined as the player's name and the realm comes from `GetRealmName`. Friend
  names are compared the same way, each word capitalised.)
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

Unknown soul (changed during build: WoW: Forever can hide names) **[user]**:
per zone, a count with first and last date (`SoulDexDB.unknown[zone]`). It
gives no points, no popup and no milestone progress, is not a unique mob,
and is not sent to friends.

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
- Tabs along the bottom: **Me · Mobs · Players · Raids · Milestones · Friends**.
  (changed during build: user asked for their own stats on a Me tab instead of a row in Friends) Mobs stays the default tab for a fresh character.
- Each collection tab has the same two columns: a **compact list on the left**
  (no bars) and a **list of names on the right**, each name with `×count`.

### 5.2 Mobs tab

- Left: places where you've caught something, under small headers:
  **Eastern Kingdoms**, **Kalimdor**, **Dungeons**. Each place shows its
  count of unique mobs on the right. Places with nothing aren't shown.
- Right: the mobs caught in the selected place. Elites, rares and bosses get
  their usual colours and markers.
- Unknown souls caught in the place show as one muted "Unknown soul ×N" row
  at the end of its list; it does nothing on click. A place with only Unknown
  souls is still listed, with a count of 0 unique mobs. (changed during build:
  hidden names on WoW: Forever.)

### 5.3 Players tab

- Left: the classes, in class colours, each with a count of unique players.
- Right: the players of that class you've sharded, with `×count`.

### 5.4 Raids tab

- Left: every raid, always listed, with `caught / total`, or a ✓ when finished
  (drawn as a built-in tick icon; see 5.5).
- Right: **every** mob in the raid. Uncaught ones show as `? ? ?`. Bosses are
  marked ☠ (a skull icon) even before they're caught, so you know what's left.
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
- Data source (changed during build: the draft left the source to the
  builder): Questie v11.38.0, `Database/Classic/classicNpcDB.lua`, the last
  tag that ships the data file. Questie is GPL-3; only NPC IDs, names, raid
  membership and the boss flag are taken, and the source is named in the
  header of `src/RaidData.lua` and in the README. The generator is
  `scripts/gen_raids.lua`. Summoned bosses (e.g. Ragnaros) have no spawn data,
  so a hand-kept boss list in the generator adds them to their raid. Built
  counts (mobs / bosses): Zul'Gurub 51/13, Molten Core 27/10, Onyxia 2/1,
  Blackwing Lair 26/8, AQ20 30/6, AQ40 34/14, Naxxramas 73/20. The boss flag
  is also set by creature rank, so Eye of C'Thun and The Master's Eye count
  as bosses.

### 5.5 Detail pane

- Clicking a name **slides a pane in from the right** (0.2 s), covering the names
  list; the left list stays visible. **[user]**
- Closed with a small **`« Back`** button in the tab style (dark purple,
  light purple text, brighter on hover) at the top left, or a `×` at the top
  right. (changed during build: WoW's default fonts lack ◀, ✕, ★, ☠ and ✓, so
  Back and close use plain "«" and "×", and the star (elite), skull (boss) and
  tick (raid done) markers are built-in texture icons. Intent kept: the
  markers are visible.) It must be easy to find without standing out. **[user]**
- Mob pane: name, rarity, "Lv 11 Humanoid · Gnoll", the flavour line, then
  caught ×N, first (date and your level), where (coordinates), last, and points.
  Raid creatures show the same rarity, level and type (older saved entries
  fill these in on their next catch); "where" is the raid's name.
- Player pane: class-coloured name, "Lv 38 Orc Rogue" (the class in the
  client's language), `<Guild>`, sharded ×N,
  first and last (date and their level), then each place with coordinates
  and a count.

### 5.6 Milestones tab

Not mocked up. Same style: a compact list of milestones, earned ones bright
with their date, the rest dimmed with how far along you are. Milestones:

- Unique mobs: 10, 50, 100, 250, 500, 1000, named "N unique mobs" (they
  count mobs only; the popup's "Soul #N" also counts players). **[user: "counts"]**
- Unique players: 1, 10, 25, 50, 100. **[call]**
- Each raid completed, and all raids completed. **[call, follows the raid dex]**

### 5.7 Friends tab

Not mocked up. Same two columns. **[user for what; call for layout]**

- Left: Soul-Dex users found in your **party, raid and guild**, plus anyone
  **added by name** (saved list, with an add box and a remove option). **[user]**
  Names may have two words (WoW: Forever's "Forgot Shards"). Hovering any row
  shows a × that removes that person: someone never added comes back if they
  send their score again; an added friend who is online is only un-added.
  (changed after 1.0.0: the user asked to be able to remove people found in the
  guild or group.) A **Clean up** button next to the add box asks first, then
  removes everyone not added who isn't in your guild or group right now.
- Each shows score, unique mobs, unique players, and raids completed. Sorted
  by score, as a leaderboard. You appear in your ranked place (highlighted,
  "(you)", not selectable) once at least one friend with a summary is listed; your numbers are on
  the Me tab (5.8). (changed during build: user asked for their own stats on a Me tab instead of a row in Friends) With nobody else
  yet your row is hidden: the left side shows the help text ("Guild and group members with Soul-Dex appear here." and "/souldex add <name>") and the right side is empty.
- Clicking someone shows their summary; a **Browse dex** button opens
  **their dex** read-only in the same window, with a visible "Viewing <name>"
  marker and a "« My dex" button back to yours. Entries they have and you
  don't are highlighted green. **[user]** (changed during build: the build
  plan put a summary and a Browse dex button first, so scores can be compared
  without fetching a whole dex over the network; the user's intent, a
  read-only view, a "Viewing" marker, a way back and highlighting, is kept.)
- People added by name are contacted directly when they're online. Offline
  people show their last known summary.
- Not limited to warlocks: anyone running the addon shows up. **[user]**
- Closing the window while browsing a friend returns you to your own dex the
  next time it opens. (changed during build: so `/souldex` never opens on
  someone else's data by surprise.)
- Network behaviour as built (changed during build: the draft left the
  protocol to the builder):
  - Everyone re-broadcasts their summary every 300 s while quiet (heartbeat);
    someone not heard from for 10 minutes shows as offline.
  - When a group or guild member we haven't heard from recently announces
    themselves, we reply with our own summary so they see us at once.
  - Added friends are whispered; Soul-Dex hides the "No player named ... is
    currently playing." line for names it whispered itself in the last 5 s,
    so offline friends cause no chat spam.
  - Browse dex whispers a request. With no dex after 60 s, a chat line says
    "No answer from X yet, asking again..." and the request is sent once more;
    with none after 90 s, "No answer from X." in chat and on the tab, and a dex
    arriving later is ignored. (changed after 1.0.0, user's call: was a silent
    5-minute wait.) A friend's dex is accepted only while we are asking that
    person; browsing someone else drops the earlier request.
  - Every incoming message is checked against the wire format and version
    before it is acted on; summary numbers must be whole, non-negative and at
    most 9 digits.
  - A browsed friend's dex carries no dates or coordinates, so its detail
    panes omit them and its Milestones show nothing earned.
  - Without AceComm (a dev checkout without `Libs/`) Friends is disabled with
    one chat line and the tab shows only the help text.

### 5.8 Me tab

(changed during build: user asked for their own stats on a Me tab instead of a row in Friends)

One full-width list of key/value lines, in this order: Score (green), Unique
mobs, Players, Raids completed, Souls taken (every catch: mobs, players, raids
and unknown souls), Zones visited (places with a mob, player or unknown catch),
Most caught (open-world and dungeon mobs only, not raid creatures or players;
mob name and `×count`, ties alphabetical, a dash when none), Top zone (most
catches including unknown souls; raid catches have no zone, so they add to Souls
taken but not to Zones visited), Unknown souls (only above 0) and Friends rank
(`#R of N` among you and the friends we hold a summary for; added people not
heard from yet are not ranked; a dash when you are alone). The header's right
side is the score. While browsing a friend's dex the tab shows their numbers
and no rank line. Redraws on a catch like the other tabs. Pure numbers:
`View.me`.

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
  list quietly: no popup, no points. **[call]** "Soul #N" in the toast is
  how many different souls the dex holds after this catch: unique mobs (raid
  creatures included) plus unique players, across all zones (a 42nd different
  soul reads "Soul #42"). **[user]** A new raid slot whose name the dex
  already has adds no soul, so its toast leaves the number out rather than
  repeat it. **[call]**
- On a **first** catch only (mob, player or raid entry), a small purple toast
  slides in near the top of the screen (0.3 s slide, 4 s hold, 0.5 s fade): "NEW SOUL CAUGHT!",
  the name, rarity, place, "Soul #N", and "+N pts". A short sound plays. **[user]**
- The popup and the sound each have their own on/off setting. **[user]**
- (changed during build: a hitch on the first popup.) The popup frame is built
  when the world first loads (only if the popup is on), not on the first catch,
  and the popup and sound come one frame
  after the bag scan that records the catch, so neither lands on that frame.
- (changed during build: the first catch still lagged; testing with the sound
  off showed it was the game reading the sound file on first play.) When the
  world first loads, behind the loading screen, the catch sound is started and
  stopped at once so it is already loaded. Only when the sound setting is on
  and the client has `StopSound` (otherwise it would be heard).
- Ticking the popup or sound box in the options builds the popup / loads the
  sound right then, so the first catch after switching one on doesn't lag either.

### 6.3 Shard tooltip

- Hovering a Soul Shard in your bags adds two lines to the normal tooltip:
  "Soul of <name>" (in rarity or class colour) and "<zone> · <date>".
  Nothing else changes. **[user]**
- (changed during build: one palette.) The tooltip, the popup and the window
  use the same rarity colours (`Rarity.lua`: elite gold, rare silver, boss
  orange, as in the mockups). The colour is saved with each shard, so shards
  named before this keep their old shade.
- (changed during build: WoW: Forever.) The addon keeps an item GUID → soul
  map (`SoulDexDB.shardSouls`), so the soul follows the shard exactly through
  moves, sorting, the bank and relogs. The tooltip lines are added through
  `TooltipDataProcessor` (item tooltips); the shard is found by the tooltip
  data's GUID, or by the bag slot the tooltip was set from. Forbidden or
  protected tooltips are left alone. Without `TooltipDataProcessor` the old
  `GameTooltip:SetBagItem` hook is used.
- An Unknown soul shard shows a grey "Unknown soul" line instead of
  "Soul of <name>", then "<zone> · <date>".
- Shards from before the addon was installed get no extra lines.

### 6.4 Guild announcements

- **On by default** for big moments only: milestones and raid completions. **[user]**
  New raid bosses are not announced. **[call]** The small milestones (10 and
  50 mobs, 1 and 10 players) are not announced; announcing starts at 100
  unique mobs and 25 unique players. **[call]**
- One switch turns them off. Only sent when you're in a guild.
- The game silently drops addon guild messages during a boss encounter (and
  Mythic+), which is exactly when a raid completes. While chat is locked
  (`C_ChatInfo.InChatMessagingLockdown`, `IsEncounterInProgress`, or a
  secret answer from either) the message is held in `SoulDexDB.announceQueue`
  and sent when the lockdown ends (`ADDON_RESTRICTION_STATE_CHANGED`,
  `ENCOUNTER_END`, leaving combat, or the next login). Held messages survive
  a reload, wait while you're not in a guild (the roster may still be
  loading), expire after an hour, are capped at 10, and are dropped if
  announcements are turned off. **[call]**

### 6.5 Flavour text

Each mob gets one silly line built from templates using its type, family,
zone and name, e.g. "A Wolf of Elwynn. Bites first, howls later." **[user]**
The choice of line is fixed per mob (seeded from its name), so it never
changes. Templates cover every creature type, with family-specific lines
where they fit: the common beast families (Wolf, Spider, Boar, Cat, Bear,
Raptor, Crocolisk, Bat, Owl, Gorilla, Hyena, Scorpid, Turtle, Carrion Bird,
Tallstrider, Crab) have their own lines; other families, and clients in other
languages, use the Beast lines. Raid creatures get flavour lines too. The
wording is the builder's call. Players get no flavour
text. **[call]**

## 7. Settings

`/souldex` opens the window. `/souldex options` (and a small gear in the
window) opens settings. `/souldex add <name>` and `/souldex remove <name>`
manage the Friends list by name; any other word prints the command list.
After each login or `/reload`, one chat line shows the addon is on:
"Soul-Dex v<version> loaded. Type /souldex or /dex to open." **[user]**
The settings:

- New-catch popup on/off
- New-catch sound on/off
- Guild announcements on/off

All saved.

## 7a. Code layout

(changed during build: the module list is owned by `CLAUDE.md`, not this
spec.) Notably the UI is split across `UI.lua` (window, tabs, panes),
`UIList.lua` (pooled scrolling list and the shared small button),
`UIFormat.lua` (text and colour helpers; rarity colours come from `Rarity.lua`) and `UIDetail.lua` (detail pane content), and the Friends network
glue and tab live in `Net.lua`.

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

One list, grouped by feature. Enable script errors first, then `/reload`.

**Startup**
- No Lua errors and no chat spam after `/reload`; in particular no "blocked
  from an action only available to the Blizzard UI" error. If a chat line
  "The game refused some events (...)" appears, report which events.
- After `/reload`, `/dump SoulDexDB.window` and `/dump SoulDexDB.friends` are
  tables (the on-load hooks ran), and `/dump SoulDexDB.shardSouls` lists the
  shards in your bags.
- After `/reload` with shards in bags, wait about 1 s: no popups, and existing
  named shards keep their tooltip lines (all bags). A shard obtained in the
  first second after login is not a catch (accepted).
- Beta-client bug (not ours): SavedVariables can fail to load after a
  reload; if the dex is suddenly empty, relog before reporting a bug.

**Catching**
- Drain Soul a mob to death and get a shard: the popup "NEW SOUL CAUGHT!"
  appears at top centre (name in rarity colour, zone, "Soul #N", "+N pts"),
  a sound plays, it holds 4 s, then fades (about 5 s in all); a second quick kill replaces it.
  The first catch after a `/reload` or a fresh login, with the sound on, shows
  it and plays the sound without a hitch, and no sound is heard at login.
  The same after logging in with the popup and sound off, then ticking both in
  `/souldex options`: no sound is heard on ticking, and the next catch has no hitch.
  The mob is listed under the right place.
- The same mob name again: no popup or sound. The same mob in another zone:
  listed there, no popup.
- Drain Soul mob A, interrupt it (move), then Drain Soul mob B to death more
  than 3 s later -> the dex records B only. Start Drain Soul on B within 3 s
  of breaking off A and kill B quickly -> the shard may stay unnamed (accepted;
  never A's name).
- Kill a mob with Drain Soul cast through a mouseover macro while targeting a
  different mob -> recorded as Unknown soul, never the targeted mob's name.
- A Shadowburn kill that yields a shard counts (untested so far: please check).
  A kill whose shard came from elsewhere, or with no Drain Soul/Shadowburn:
  no catch, no name.
- If the game hides a target's name (it shows as secret/"Unknown"): the
  catch appears as a muted "Unknown soul ×N" row at the end of that zone's
  list; no popup, no sound, no points, the unique-mob count does not change.
- Dungeon (party) kills are grouped under "Dungeons". A raid kill fills its
  slot in the Raids tab and is not listed under Mobs. A PvP Drain Soul kill
  appears under the player's class with class, race and guild.
- `/dump SoulDexDB.shardSouls` after catches shows entries keyed by item GUID,
  each `{ soul = <table or false>, seen = <time> }`; `SoulDexDB.shardSlots`
  is gone.
- With the bank open, or an item on the cursor, take a shard from a Drain Soul
  kill: it stays unnamed (accepted). Then, within a few seconds, take a shard
  from the mailbox or a trade: that one stays unnamed too, never the mob's name.
- Drain Soul a mob to death with the mailbox, a trade or a vendor window open:
  the shard stays unnamed (accepted).
- The popup's "Soul #N" counts every different soul in your dex (mobs, raid
  creatures and players, all zones): with 41 already, a new one reads
  "Soul #42". Players and raid creatures show it too.
- Drain Soul a raid creature: its detail pane (Raids tab) shows its rarity
  (Elite / Boss) and a "Lv 60 Humanoid" style line, if the game gave a level.

**Shard tooltip**
- Hover the new shard: two extra lines, "Soul of <name>" (coloured) and
  "<zone> · <date>"; an Unknown soul shard shows a grey "Unknown soul" line.
  Old or unmatched shards get no extra lines. Move the shard to another bag,
  sort the bags, put it in the bank and take it out, relog: the line stays on
  that exact shard.

**Window**
- Log in or `/reload`: one chat line "Soul-Dex v<version> loaded. Type
  /souldex or /dex to open." (with a version number such as "v1.1.0", not
  "dev", in a built copy; "dev" only in an unbuilt checkout).
- `/souldex` opens a small dark-purple window with the score at the top right,
  a gear and a ×, and tabs Me · Mobs · Players · Raids · Milestones · Friends.
  `/souldex`, Escape or × closes it.
- Drag the title bar; `/reload` and reopen: same position and same last tab.
- Mobs: group headers (Eastern Kingdoms / Kalimdor / Dungeons) with places and
  counts; elites gold with a star icon, rares silver, world bosses orange with
  a skull icon. With many rows the wheel scrolls; clicking a place near the
  bottom of a scrolled left list keeps its scroll, the right list starts at
  the top, and a new catch moves neither list.
- Click a mob: a darker pane slides in over the names (about 0.2 s) with name,
  "Lv 11 Humanoid · Gnoll", flavour line, Caught x N, First, Where, Last and
  green points. "« Back" (brightens on hover) and × close it; clicking a place
  or another tab closes it at once.
- Players: class-coloured groups; the player pane shows class, race, guild,
  first and last with level, places with coordinates, points.
- Raids: every raid with caught/total or a tick icon; uncaught mobs show as
  dim "? ? ?" (bosses with a dark skull) and do nothing on click.
- Milestones: earned ones white with a date, the rest dimmed with progress.
  Crossing one prints a chat line; a guild message goes out only for the
  announce milestones (100 mobs, 25 players, raids), only in a guild with
  announcements on.
- Announcement during a lockdown: `/console addonChatRestrictionsForced 1`,
  then earn an announce milestone (or a raid completion during a boss
  fight). Only the "Milestone earned" chat line appears, no guild message.
  `/console addonChatRestrictionsForced 0` (or kill the boss): the guild
  message appears once. With it held, `/reload` and turn the restriction
  off: it still goes out once.

**Settings and commands**
- `/souldex options` or the gear opens three checkboxes (popup, sound, guild
  announcements); clicking the label text toggles too. Untick each in turn,
  `/reload`: still unticked, and the matching behaviour stops.
- `/souldex help` (or any unknown word) prints the commands.
- `/dex`, `/dex options`, `/dex add <name>` do the same as their `/souldex`
  forms.

**Raid data**
- In a raid, `/dump UnitGUID("target")` on a mob: the sixth dash-separated
  field of the GUID is the NPC ID and must match that mob's id in
  `src/RaidData.lua`. Check at least one boss and one trash mob.

**Me tab**
- Me is the left-most of six tabs and all fit in the window. It lists Score,
  Unique mobs, Players, Raids completed, Souls taken, Zones visited, Most caught,
  Top zone, (Unknown souls only if you have any) and Friends rank ("#2 of 3", or
  a dash with no friends seen). A new catch updates it while open; browsing a
  friend shows their numbers without a rank.

**Friends** (two players A and B on a packaged build, same realm)
- Same guild: within about 5 s of login the Friends tab on both lists both
  names by score, you in your ranked place marked "(you)". Alone, your row is
  hidden, the left side shows the help text ("Guild and group members with Soul-Dex appear here." and "/souldex add <name>") and the right side is empty.
- Click the other person: Score, Unique mobs, Players, Raids completed, online.
- A clicks Browse dex: "Asking B..." then B's dex fills every tab, the title
  reads "Soul-Dex · Viewing B" with a "« My dex" button, and entries B has and
  A lacks are green. A catch made while browsing does not change the view;
  "« My dex" returns to A's own dex including it. Close the window while
  browsing, then `/souldex`: it opens on A's own dex.
- Not in a guild: a party invite makes each appear within 30 s.
- Not grouped: typing B's name into "Add..." (Enter), or `/souldex add B`,
  shows B within about a minute; hovering the row shows a × that removes B
  (or `/souldex remove B`). Do this with B's full two-part name (for example
  `/souldex add Forgot Shards`): B is added, and B's score appears once B is
  online. **Please check** that whispers to a two-part name reach B (if not,
  B never appears; tell the builder).
- Hover a guild member you never added: a × shows and removes them; they come
  back on their next score update.
- Click "Clean up" beside the add box: a dialog asks first; "Remove" drops
  everyone you didn't add who isn't in your guild or group right now and
  prints how many; "Cancel" changes nothing.
- An offline or misspelt name causes no "No player named..." spam; the row
  stays dimmed ("Not heard from yet."). Browsing an offline person: after
  60 s a chat line "No answer from X yet, asking again...", after 90 s
  "No answer from X." in chat and on the tab.
- Browse A, then quickly browse B: only B's dex opens, even if A answers late.
- B logs out: about 10 minutes later B is dimmed, "offline" and "Last seen
  <date>". A catch on B updates B's score on A within about 30 s (guild/group)
  or 60 s (added friend only).
- A dev checkout without `Libs/`: one chat line "Friends are offline:
  AceComm-3.0 is missing...", no Lua errors.

### Known limitations

- Newcomer replies can be sent needlessly near the 6-minute mark (the newcomer
  threshold is only one poll tick above the 300 s heartbeat).
- Added friends who are offline are asked every 60 s with no back-off (their
  "not playing" notices are hidden).
- Alt-Z (hiding the UI) resets browsing to your own dex.
- A browsed friend's Milestones tab shows nothing earned (no dates are sent).
- Raid data is Classic Era and may need regenerating for WoW: Forever content.
- WoW: Forever can hide target names (secret values): those catches are only
  counted as "Unknown soul" per zone.
- Shadowburn catches are untested in game.
- WoW: Forever beta bug: SavedVariables can fail to load after a reload.
- A shard refunded by a demon that despawns during a Drain Soul (or within
  3 s after it) would take the drain target's name, and the real shard from
  the kill then stays unnamed.
- A shard gained while the bank, mailbox, trade or vendor window is open or an
  item is on the cursor, or while any bag slot is unreadable (this scan or the
  previous one), is never named; nor is a kill shard that arrives in the same
  bag scan as another new shard.
- Clean up uses the guild roster the game has cached; if it is stale, a guild
  member may be removed and comes back on their next score update.
- A Drain Soul started within 3 s after another one ended on a different
  target, with no shard from the first, leaves the next shard unnamed.
