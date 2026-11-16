# SoulDex — design

Date: 2026-11-10
Status: approved and built. Deliberate differences from the first draft are marked "(changed during build: ...)".

## 1. What it is and why

SoulDex is a World of Warcraft: Forever addon for warlocks. It turns
collecting Soul Shards into a collection minigame, like a Pokédex: every time
a shard lands in your bags, the mob or player it came from is "caught" and
recorded in the dex.

Warlocks collect shards all the time anyway. SoulDex gives that chore a
collector's goal, a record of where your souls came from, and something to
compare with other warlocks.

(changed after 1.2.4: rebrand.) The user found the first branding "too
heartfelt about the journey of a soul" and asked for a game: "cool, polished,
WoW, warlock, premium". **[user]** The voice is now a soul hunter's: souls are
**claimed** (not "caught"), every claim is a trophy, the score earns a warlock
**rank** (6.6), milestones have names, and lists show progress bars. The
tagline is "Their souls. Your collection." **[user, from a list]** The code still says
"catch" in its own names; only what players read changed.

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
- The shard in your bag says whose soul it is in its tooltip. **[user]**
- A minigame layer: a popup and sound for new catches, points, milestones,
  and guild announcements of big moments. **[user]**
- Social: see other SoulDex users in your party, raid or guild, plus anyone
  you add by name. View their score and browse their dex. **[user]**

### Non-goals

- No master list of open-world mobs, and no "X / Y" for zones. **[user]**
- No 3D model portraits. **[user]** (left out when choosing what an entry shows)
- No change to the shard item, its icon, or how bags look. Tooltip text only. **[user]**
- No content past vanilla for now. Raid data starts from classic vanilla
  (MC, Onyxia, BWL, ZG, AQ20, AQ40, Naxxramas). WoW: Forever plans new content;
  the raid list must be easy to extend later. **[user]**
  (changed after 1.2.4: Forever raids.) Beta testers asked for Forever's own
  instances. Its two new raids, The Barrow Deeps and Hyjal Summit, are now
  listed with their contents TBD (5.4). **[user: "raids now, dungeons later"]**
  The nine new 5-player dungeons are still out and get their own plan; their
  catches stay under Mobs > Dungeons.
- No points for repeat catches. **[user]**
- No minimap button of its own. **[call]** Opened with `/souldex`.
  (changed after 1.3.0: review of standard addon comforts.) SoulDex is listed
  in the game's own addon list by the minimap (the addon compartment), and has
  a key binding; neither adds anything to the screen (7).
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
- Same project setup as the user's other addons: `src/` modules sharing code through `ns`,
  pure logic kept apart from WoW glue and tested with busted via
  `LoadAddonFile`, `luacheck` with every WoW API declared, `scripts/build.sh`,
  `.pkgmeta`, a `CHANGELOG.md`, and a `CLAUDE.md` like theirs. **[call]**
- Libraries: AceComm-3.0 (and its dependencies) via `.pkgmeta` externals pinned
  to an Ace3 tag, for chunked addon messages. Nothing
  else. **[call]**
- Name in game: **SoulDex**. Slash command: **`/souldex`**, with **`/dex`**
  as a short form that works for every subcommand (`/sd` is left alone: too
  likely to clash with another addon). **[user]**
  The folder, `.toc` and code name can stay `SoulShardPokeDox` or become
  `SoulDex`; that's the builder's choice. (Built as `SoulDex`: `SoulDex.toc`,
  `package-as: SoulDex`, `SoulDexDB`.)
- Chat output: personal messages go to the player's own chat frame only. The
  two exceptions are guild announcements and the hidden `SDX1:` whispers
  SoulDex sends to the player themself to read a hidden target name (4.2).
  Those lines are hidden by a chat filter and never reach anyone else. **[user]**
  (changed after 1.2.4: soul names through a self-whisper; full reasoning in
  `docs/superpowers/specs/2026-11-15-soul-name-whisper-design.md`.)

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
  any other unreadable spell event ends it 3 s later. A new Drain Soul ends an
  older Drain Soul capture 3 s later (only one channel runs at a time); it
  never shortens a Shadowburn capture, whose target keeps its 5 s to die.
  (changed after 1.3.0: a Drain Soul started on another mob used to cut the
  Shadowburn capture short, so a Shadowburned mob dying late in its 5 s gave
  its shard the drained mob's name.)
- One capture names **one** shard (one channel kills one target); further new
  shards in the same window are soulless. If two unused captures on different
  targets are live at once (a new Drain Soul within 3 s of the last one
  ending), neither names a shard. (changed after 1.3.0.) Two exceptions, both
  for hidden names, where the GUID can't tell targets apart: a capture taken
  with no target change since the previous one (`PLAYER_TARGET_CHANGED` is
  counted) is the same target, so a recast on the same mob replaces the older
  capture instead of making both ambiguous; and captures that can all only
  become an Unknown soul (hidden name, no whisper out) give the same result
  whichever is picked, so the newest is used and all are spent. Two new shards in the same bag scan can't be
  told apart: neither is named, and the capture is spent. A new shard stored
  as soulless by a quiet scan (below) also spends the capture, so it can't
  name a later shard from a trade or the mailbox instead.
- **Unknown soul [user].** When the target's name is hidden (secret, empty,
  or "Unknown"), or there is no target name at all (a focus or mouseover
  macro), the catch is recorded as an Unknown soul in that zone (see 4.4).
  Players whose name is hidden go there too. A hidden name is first asked for
  by the soul-name whisper (next bullet); Unknown is the fallback when it
  can't be asked for or no name comes back.
- **Soul-name whisper [user].** (changed after 1.2.4: in dungeons the target's
  name and GUID are secret, which made every dungeon catch an Unknown soul.)
  The game still expands `%t` to the target's name when you send chat, so at
  Drain Soul channel start or Shadowburn success SoulDex sends
  `SDX1:<token>:%t` as a whisper to `GetUnitName("player", true)`, and reads
  the name from the reply. The token is short hex built from the send time
  and a counter, so a reply to a whisper sent before a `/reload` can't match
  a new one. It sends only when all of these hold:
  - the chat filter that hides `SDX1:` lines was installed (no filter API, no
    whisper);
  - the target's name is secret (not a name mismatch);
  - a target exists, and `mouseover` and `focus` are not a different unit
    (`UnitIsUnit`; anything unreadable means no);
  - the cast's SENT event did not name a readable unit;
  - the target did not change between the cast's SENT event and the send
    (changed after 1.3.0: the spell's target is fixed at SENT but `%t` names
    the target at the send, so a Tab during the latency named the wrong soul;
    a target change before SENT, as a targeting macro makes, is fine);
  - chat is not locked down (`InChatMessagingLockdown`; unreadable counts as
    locked), because sending then shows a red "Interface action failed" error;
  - the player is not AFK or DND (their auto-reply would show a line).
  One whisper per capture. A reply counts only if its token is pending, its
  sender GUID is the player's own, and its name is plain (no `|`, `:`,
  newline, `%t`, empty or overlong). A reply that arrives secret (combat) is
  re-read from chat history when restrictions lift. `SDX1:` whispers to and
  from the player are hidden by a chat filter (a reply whose text arrives
  secret can't be checked, so it may show), and `/r` is put back after
  sending if the send moved it (it is not written otherwise: every write into
  the chat box's state from addon code is a chance to taint it), and again
  when the reply arrives or the wait ends if it then points at the player. A shard whose name is pending is held: its tooltip
  shows the grey
  "Unknown soul" with "<zone> · name pending", and nothing is recorded. When
  the name arrives it is recorded like an open-world catch (popup, sound,
  points). With no reply it becomes an Unknown soul after 60 s of unrestricted
  time (out of combat, chat unlocked), at most 600 s after sending. A held
  shard still pending at login becomes one Unknown soul. If the game blocks a
  SoulDex action (`ADDON_ACTION_BLOCKED` or `ADDON_ACTION_FORBIDDEN` naming
  SoulDex in arg 1), SoulDex sends no more whispers that session, every
  waiting whisper fails at once (a held shard becomes one Unknown soul), and
  one line in your chat says so. In a dungeon the
  creature type and family are secret, so a soul named this way is recorded
  without them; a later catch of the same creature fills them in and tops up
  its points (a top-up counts toward a rank-up). (changed after 1.4.0-beta.1.)
  In a raid SoulDex lists, the name alone finds the creature's slot in that
  raid's list, so a raid soul named by whisper is recorded in its raid (a boss
  with its boss points), whether the name came before or after the shard; the
  catch context saved with a held shard carries the instance type and id for
  this. Full reasoning and probe results: `docs/superpowers/specs/2026-11-15-soul-name-whisper-design.md`.
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
  look new. Only the login scan forgets long-unseen shards. (changed after
  1.3.0.) The shard map is changed in place: a scan touches only the shards in
  the bags and never copies the map, which holds every shard seen and used to
  be rebuilt after every spell cast.
- Shards that were already in the bags when the addon started, or that can't
  be matched, are remembered as "seen, no soul" (soulless), so they never get
  a name later. Shards that leave the bags are kept (bank, mailbox); a login
  baseline forgets shards not seen for 30 days. (changed after 1.3.0: a spent
  shard never comes back, and the saved map grew by every shard farmed in a
  month.) The login baseline also forgets soulless shards that have been out
  of the bags for a day, and keeps at most the 400 most recently seen shards
  that are out of the bags; a banked shard beyond that loses its tooltip name
  (the dex entry is untouched). A shard still waiting for its name is never
  forgotten.
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
  Exception: a raid creature named by the soul-name whisper (4.2) has no GUID,
  so no NPC ID: it is recorded as a mob under Mobs > Raids, like a raid
  SoulDex doesn't list, and doesn't count toward its raid's list or Raid
  Reaper. **[accepted, whisper design record 5.4]**
  (changed after 1.2.4: Forever raids.) A raid the data lists without an
  instance ID (a TBD raid, 5.4) is matched by its instance name the first time
  a soul is claimed inside a raid-type instance: the name `GetInstanceInfo`
  gives, compared without case or a leading "The". The ID is then saved per
  character in `SoulDexDB.instances` (raid key to instance ID) and applied on
  every load. A saved ID that is damaged, names an unknown raid, or belongs to
  another raid is ignored. **[call]**

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
and is not sent to friends. A hidden name is no longer always Unknown: see
the soul-name whisper in 4.2. Bosses killed during their encounter, and
casts the whisper guard refuses, still end here.

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
- Title bar: "SoulDex · <tab>", plus the total for that tab and the score.
- Tabs along the bottom: **Me · Mobs · Players · Raids · Milestones · Friends**.
  (changed during build: user asked for their own stats on a Me tab instead of a row in Friends) Mobs stays the default tab for a fresh character.
- Each collection tab has the same two columns: a **compact list on the left**
  and a **list of names on the right**, each name with `×count`.
- (changed after 1.2.4: rebrand.) A row can carry a **progress bar**: a 2 px
  fel-green line along its bottom over a dark track. Used for an unfinished
  raid in the Raids list, an unearned milestone, and the way to the next rank
  on the Me tab. **[call]**
- An empty Mobs tab reads "No souls claimed yet. Go drain something."
- (changed after 1.2.4: UI rework.) The user approved a sheet of 18 numbered
  changes ("I wanna do them all"). **[user]** For the whole window:
  - It is **380 × 280** (was 360 × 232), shaded lighter purple at the top to
    near-black at the bottom (flat fill on clients without texture gradients).
  - The title bar starts with the **rank emblem** of the dex on screen (a
    friend's while browsing; changed after 1.2.4: rank emblems.) **[user]**
    Right of the title: the **rank chip** (the rank's name in fel green in a small dark
    box), then the tab's total and the score.
  - Under the title, in place of the rule, a 2 px **rank progress line**: a
    dark track filled in fel green as far as the way to the next rank. The
    chip and line follow the dex on screen (a friend's while browsing).
  - The selected row on the left has a 2 px fel-green marker on its left
    edge; the active tab has a fel-green underline.
  - Rows of souls have a 2 px stripe on their left edge in the soul's rarity
    colour (dull purple for ordinary mobs).
  - (changed after 1.3.0.) The window's size can be set from 60% to 160% in
    steps of 10% in the options (or to any 5% with `/souldex scale <percent>`);
    the scale is saved with the position. `/souldex reset` and the options'
    "Reset window" put it back in the middle of the screen at 100%. The gear
    has a tooltip ("Options"). **[call]**
  - (changed after 1.2.4: rank emblems.) The emblems ship in `art/` as
    64 × 64, 32-bit, uncompressed TGA: original art, one per rank (6.6); no
    game art stands in for them. **[user]**

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
- (changed after 1.2.4: Forever raids.) **TBD raids.** WoW: Forever's own
  raids are hand-kept in `src/ForeverData.lua`, beside the generated file
  (which stays Questie-only), and are listed first, above the vanilla raids:
  they are the ones in the game today. **[call]** What is known comes from
  Blizzard's "World of Warcraft: Forever Raid Overview" (news 24303009, read
  2026-11-15); boss names, creature lists and instance IDs are not published,
  and both raids open on 2026-12-09:

  | Raid | Players | Bosses |
  |------|---------|--------|
  | The Barrow Deeps | 10 | 8 |
  | Hyjal Summit | 20 | 13 |

  Such a raid is marked `tbd` in the data, with no creature list and no
  instance ID (learned in game, 4.3). In the Raids list its row reads `TBD`,
  or `N / ?` once N different souls were claimed there, with no progress bar
  and no tick. **[call]** Its right pane starts with the note "Roster still
  sealed: 8 bosses wait inside. Every soul you claim here is kept." (the
  raid's boss count), followed by the souls claimed there. Those are kept as
  unlisted entries under the raid, by NPC ID, and fill their slots when the
  real list ships. A TBD raid is **listed, not counted**: it is left out of
  the Raids header total, the Me tile's "N / M", its own "<Raid> Drained"
  milestone and Raid Reaper until its data ships. **[user]** When the data is
  known, the entry gets its `instanceID` and `mobs` and loses `tbd`. Forever
  dungeons, when planned, go in the same file.

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
  Claimed ×N, first (date and your level), where (coordinates), last, and points.
  Raid creatures show the same rarity, level and type (older saved entries
  fill these in on their next catch); "where" is the raid's name.
- Player pane: class-coloured name, "Lv 38 Orc Rogue" (the class in the
  client's language), `<Guild>`, sharded ×N,
  first and last (date and their level), then each place with coordinates
  and a count.

(changed after 1.2.4: UI rework.) The pane is drawn as a **trophy card**
(`UIFormat.mobCard` / `playerCard`, `UIDetail.lua`), top to bottom:

- A header band tinted in the soul's colour (rarity or class), fading down.
  In it: an icon with a border in that colour (one of the game's icons for
  the creature type, by its English name; for other languages and unknown
  types the rank emblem of the dex on screen, uncropped, on a dark backing
  (changed after 1.2.4: rank emblems.) **[user]**; a crossed-swords icon for
  players), the name in that
  colour, a line "Elite · Lv 11 Humanoid · Gnoll" (players: "Lv 38 Orc
  Rogue"), and the points as a badge at the top right.
- The flavour line, set off by a bar on its left, without quote marks.
- Mastery (6.1), for souls that earn stars: a row of eight stars, lit ones
  fel green and the rest dark, "+N" after it past eight; "12 / 25 to next
  star" on the right; a 3 px bar under it.
- Four cells in a 2 × 2 grid, each a small caps label over its value.
  Mobs: Claimed, First, Where, Last. Players: Sharded, Guild, First, Last.
  A missing value is a dash.
- Players: their places listed below the cells (scrolls).
- "« Back" at the bottom right closes it; the "×" is gone (the badge sits
  there). **[call]**

### 5.6 Milestones tab

Not mocked up. Same style: a compact list of milestones. Each has a **name**
and a plain goal beside it ("A Hundred Voices · 100 unique mobs"). Earned
ones show the name in fel green and their date; the rest are dimmed with how far
along you are and a progress bar. (changed after 1.2.4: rebrand; names are
the builder's call.) Milestones:

- Unique mobs: 10 First Harvest, 50 Soul Collector, 100 A Hundred Voices,
  250 Shard Hoarder, 500 Soul Baron, 1000 A Thousand Souls; goal "N unique
  mobs" (they count mobs only; the popup's "Soul #N" also counts players).
  **[user: "counts"]**
- Unique players: 1 First Blood, 10 Headhunter, 25 Menace, 50 Dreaded,
  100 Nemesis; goal "First player soul" / "N player souls". **[call]**
- Each raid completed: "<Raid> Drained", goal "every soul". All raids
  completed: "Raid Reaper", goal "every raid drained". **[call, follows the
  raid dex]** (changed after 1.2.4: Forever raids.) TBD raids (5.4) have no
  "Drained" milestone and are not part of Raid Reaper's goal. **[user]**

In chat and guild messages a milestone reads "<name> (<goal>)".

(changed after 1.2.4: UI rework.) The list is **grouped** under MOBS, PLAYERS
and RAIDS, each header with "N of M" earned on the right
(`UIFormat.milestoneGroups`). Under a header come the milestones still to
earn, so the next goals are on top; then one fel-green row with a tick,
"N earned", which opens and closes that group's earned milestones (newest
first) when clicked. Groups start closed each session. **[user for grouping,
the mark and collapsing; call on click-to-open]** The mockup's round
medallion is the tick icon on the "N earned" row: the game has no ready-made
lit/unlit medallion. **[call]**

### 5.7 Friends tab

Not mocked up. Same two columns. **[user for what; call for layout]**

- Left: SoulDex users found in your **party, raid and guild**, plus anyone
  **added by name** (saved list, with an add box and a remove option). **[user]**
  Names may have two words (WoW: Forever's "Forgot Shards"). Hovering any row
  shows a × that removes that person: someone never added comes back if they
  send their score again; an added friend who is online is only un-added.
  (changed after 1.0.0: the user asked to be able to remove people found in the
  guild or group.) A **Clean up** button next to the add box asks first, then
  removes everyone not added who isn't in your guild or group right now.
  (changed after 1.3.0.) When it can't tell who is there (in a guild whose
  roster hasn't loaded, or a name that can't be read) it removes nobody and
  says "Can't read your guild and group right now, so nobody was removed. Try
  Clean up again in a moment." It used to take a member's guild rank for part
  of their name, and an unloaded roster for an empty guild. People never added
  and not heard from for 30 days are also dropped at login, so the list and
  "Among friends" don't fill with everyone you once grouped with.
- Each shows score, unique mobs, unique players, and raids completed. Sorted
  by score, as a leaderboard. You appear in your ranked place (highlighted,
  "(you)", not selectable) once at least one friend with a summary is listed; your numbers are on
  the Me tab (5.8). (changed during build: user asked for their own stats on a Me tab instead of a row in Friends) With nobody else
  yet your row is hidden: the left side shows the help text ("Guild and group members with SoulDex appear here." and "/souldex add <name>") and the right side is empty.
  (changed after 1.3.0.) Only your own row is hidden then: a friend you added
  who hasn't answered yet stays listed, so they can be selected and removed;
  the help text shows only when nobody is listed.
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
  - Added friends are whispered; SoulDex hides the "No player named ... is
    currently playing." line for names it whispered itself in the last 5 s,
    so offline friends cause no chat spam.
  - Browse dex whispers a request. With no dex after 60 s, a chat line says
    "No answer from X yet, asking again..." and the request is sent once more;
    with none after 90 s, "No answer from X." in chat and on the tab, and a dex
    arriving later is ignored. (changed after 1.0.0, user's call: was a silent
    5-minute wait.) A friend's dex is accepted only while we are asking that
    person; browsing someone else drops the earlier request.
  - (changed after 1.3.0: a dex goes out at a few hundred bytes a second, so
    a large one could never arrive within 90 s, and the second ask made the
    sender send it twice.) Before the dex the sender whispers its size ("W").
    From then on the asker waits as long as that size needs (300 bytes a
    second assumed, plus 30 s, at most 10 minutes), does not ask again, and
    the tab reads "Receiving X's dex... ~N min". If it still doesn't come:
    "X's dex didn't arrive in time." An older SoulDex on the other side sends
    no size, and the 60 s / 90 s rule above applies unchanged.
  - The sender sends one dex at a time: while one is going out, further
    requests from anyone are ignored (they time out on the asker's side), and
    10 s must pass between dexes to different people (30 s to the same one).
    Anyone who whispers a request still gets the dex; that is not limited to
    friends. **[call; see Known limitations]**
  - A dex that arrives after the window was closed doesn't reopen it: one
    chat line says it arrived and to press Browse dex again.
  - An entry that can't be put on the wire (no name, a negative number) is
    left out of the dex sent, so one damaged entry no longer makes the whole
    dex unreadable for every friend.
  - The version is sent ("V") to the guild and group once per login and when
    someone new is heard, and once by whisper to each person who asks for a
    summary; see 7 for the notice.
  - Every incoming message is checked against the wire format and version
    before it is acted on; summary numbers must be whole, non-negative and at
    most 9 digits.
  - A browsed friend's dex carries no dates or coordinates, so its detail
    panes omit them and its Milestones show nothing earned.
  - Without AceComm (a dev checkout without `Libs/`) Friends is disabled with
    one chat line and the tab shows only the help text.

### 5.8 Me tab

(changed during build: user asked for their own stats on a Me tab instead of a row in Friends)

(changed after 1.2.4: UI rework; it replaced a plain list of key/value lines.)
Three parts (`View.meCard`, numbers from `View.me`):

- **Rank crest**, the left column: the rank's emblem (changed after 1.2.4: rank
  emblems.) **[user]**, the rank's name in fel
  green, "RANK N OF 8", the score, a 4 px bar to the next rank and
  "<points> pts to <rank>" ("The highest rank" at the top).
- **Six tiles**, two rows of three: Unique mobs, Players, Raids ("1 / 7"
  completed; TBD raids, 5.4, are not in the 7), Mastery (stars, fel green, with a star), Souls taken (every
  catch: mobs, players, raids and unknown souls), Among friends (`#R of N`
  among you and the friends we hold a summary for; a dash when alone). While
  browsing a friend the last tile is Zones instead.
- **Records**, a list under the tiles: Most claimed (open-world and dungeon
  mobs; name and `×count`, ties alphabetical), Nemesis (the player sharded
  most, in class colour), Hunting ground (the zone with most catches),
  Rarest trophy (a boss before a rare before an elite; the earliest of
  equals), Latest (the last soul claimed, with "today", "yesterday" or the
  date, by your local calendar days; changed after 1.3.0: they went by UTC
  days, so an afternoon claim read "yesterday" by evening in the Americas), Best day ("41 souls · 9 Nov 26"), Zones hunted (not while browsing)
  and Unknown souls (only above 0). A record with nothing to show is a dash.
  **[user: highlight the fun data; call on which records]**
- Best day needs data the dex never kept: from this version every catch is
  counted into `db.today` and the highest day kept in `db.best` (UTC days, as
  in 6.1), so it starts from the update. **[call]**

Redraws on a catch like the other tabs.

## 6. Game layer

### 6.1 Points

A **first** claim scores the most; uniqueness stays the core. **[user]**

| Soul | First claim |
|------|-------------|
| Normal mob | 1 |
| Elite | 5 |
| Rare / rare elite | 10 |
| Boss (world boss classification, or raid boss in the data) | 25 |
| Player | 10 |

Raid trash uses the same table by its classification. **[call on values;
the user agreed to this table as an example]**

(changed after 1.2.4: until then repeats were counted and never scored.) The
user wanted a way to keep earning points for warlocks who install late or
farm one spot, "without the ability to it to be abused". **[user]** Claiming a
soul **again** now scores by what it is:

| Soul | Claiming it again |
|------|-------------------|
| Raid boss, world boss | The same 25 points, every claim: "a kill is a kill" and lockouts limit it. The user kept this after seeing it outpace PvP long term: you aren't always raiding with the same group. **[user]** |
| Player | 3 points, at most once a day for each player. **[user: "a few points", so a PvP-only warlock keeps pace with a raider; 3 and "per player" are the builder's reading]** |
| Rare / rare elite | 2 points, at most once a day for each rare. **[call]** |
| Everything else (normal, elite, raid trash) | Mastery stars, below. **[user]** |

**Mastery.** Claims of the same mob (all zones together) earn it stars at 10,
25, 50, 100, 250, 500, 750 and 1,000 claims, then one more star every 500 claims,
with no end. **[user: runway to 1,000, several milestones, one of them at
750, a star every 500 after]** Each star pays points once: 1, 1, 2, 3, 5, 8, 8
and 10 for the first eight (38 in all), then 5 for each later star; an elite
earns double.
**[call on thresholds below 1,000 and on values]**

- "A day" is a UTC calendar day (`floor(time / 86400)`), compared with the
  soul's previous claim: a second claim on the same day, or with a clock that
  went backwards, pays nothing. **[call]**
- Past claims are credited. Stars and boss repeats are worked out from the
  saved claim counts (`Points.mobWorth`), so an existing dex gains them on
  update with no migration. Daily points for players and rares are kept in
  the entry's `bonus` and start from the update. **[call]**
- Which rule applies: classification `worldboss` or 25 first-claim points is a
  boss; `rare` / `rareelite` is daily; anything else is mastery (`Points.rule`).
- A friend's dex arrives with each soul's full worth in its points (the wire
  format is unchanged) and is scored at face value (`db.flat`). Their mobs
  still show stars from their counts; their raid creatures show none.
- Shown: rows put the stars before the count ("3★ ×212", a fel-green star so
  it isn't read as the elite's yellow star); the detail pane has a "Mastery"
  line, "3★ · 212/250" with a progress bar to the next star; the points line
  is everything that soul has scored; the Me tab has "Mastery stars".
- A claim that earns a star shows the popup even though the soul isn't new:
  title "MASTERY: N STARS" in fel green, then "<zone> · ×N claimed" and the points,
  with the sound, and a chat line "Mastery: <name> reached N stars (+N pts)."

### 6.2 New-soul popup and sound

- Catching a mob you already have, in a new place, adds it to that place's
  list quietly: no popup, no points. **[call]** "Soul #N" in the toast is
  how many different souls the dex holds after this catch: unique mobs (raid
  creatures included) plus unique players, across all zones (a 42nd different
  soul reads "Soul #42"). **[user]** A new raid slot whose name the dex
  already has adds no soul, so its toast leaves the number out rather than
  repeat it. **[call]**
- On a **first** catch only (mob, player or raid entry), a small purple toast
  slides in near the top of the screen (0.3 s slide, 4 s hold, 0.5 s fade): a title,
  the name, place, "Soul #N", and "+N pts". A short sound plays. **[user]**
- (changed after 1.2.4: rebrand.) The title names what was claimed: "SOUL
  CLAIMED", "ELITE SOUL CLAIMED", "RARE SOUL CLAIMED", "RARE ELITE SOUL
  CLAIMED", "BOSS SOUL CLAIMED" or "PLAYER SOUL CLAIMED"; the rarity is no
  longer repeated after the name. The popup's border and title take the soul's
  colour (rarity or class colour; purple for an ordinary mob). **[call]**
- (changed after 1.2.4: the user found the first rebrand had "too much gold" and wanted it
  "darker and demonesque".) Ranks, milestone names and rank-ups use fel green
  (`9dff3a`), not gold; the flavour line in the detail pane is a soft violet
  (`b9a6d9`), not yellow. Gold is left to elites, where the game itself uses it. **[user]**
- A soul named by whisper (4.2) gets its popup and sound when the name
  arrives, possibly a few seconds after the shard, or after combat. **[user]**
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

- (changed after 1.2.4: UI rework.) The popup is 330 px wide with a 3 px bar
  on its left edge and a fade of the same colour behind the icon (the soul's
  colour; fel green for a mastery star). The points are no longer in the
  second line: they stand large on the right ("+25" over "PTS"). As it lands
  a band of light crosses it once (0.45 s). **[user]**
- (changed after 1.2.4: rank emblems.) The popup's icon is your rank emblem
  after the claim (so the claim that ranks you up shows the new one); the
  rank-up popup's is the new rank's. **[user]**
- A rank-up no longer borrows the soul's popup. A second popup appears under
  it: "RANK UP", the rank in fel green, "Rank 4 of 8 · next: Reaper at 2,500"
  ("the highest rank" at the top), and the score on the right. **[user]**
- Sounds: the level-up fanfare for a rank-up, a heavier loot chime for a boss
  (any creature claim worth 25 or more), the usual chime otherwise
  (`Capture.soundFor`). Only the usual chime is loaded ahead at login, so the
  other two may hitch the first time they play. **[user for different
  sounds; call on which]**

### 6.3 Shard tooltip

- Hovering a Soul Shard in your bags changes its tooltip: the item name line
  ("Soul Shard") becomes "Soul of <name>" (in rarity or class colour), and a
  "<zone> · <date>" line is added at the bottom. Nothing else changes. **[user]**
  (changed after 1.2.4: the user wanted the name in the title, not repeated
  under "Soul Shard".) If the name line can't be found, "Soul of <name>" is
  added as a line instead.
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
- An Unknown soul shard shows a grey "Unknown soul" as its name instead of
  "Soul of <name>", then "<zone> · <date>".
- A shard held while its name is pending (4.2) shows the same grey "Unknown
  soul" with "<zone> · name pending", and becomes "Soul of <name>" when the
  name arrives.
- Shards from before the addon was installed keep the plain "Soul Shard" tooltip.

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

- (changed after 1.2.4: rebrand.) Reaching the rank of Reaper or higher
  (rank 5 of 8, 2,500 points) is announced the same way: "SoulDex: reached the
  rank of <rank>!". Lower ranks are not. **[call]**

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

### 6.6 Ranks

(added after 1.2.4: rebrand.) The score earns a warlock rank. **[call on
names and thresholds]**

| Rank | Name | From (points) | Emblem |
|------|------|---------------|--------|
| 1 | Initiate | 0 | The shard only, at 60 % scale, its faces greyed, no glow: a dull grey sliver |
| 2 | Acolyte | 50 | Full-size violet shard on a soft violet glow |
| 3 | Soul Thief | 250 | + the dark disc and a thin plain iron band (no rivets) |
| 4 | Shardbinder | 1,000 | + the full band (keyline, bevel, lit and shadowed rims) with its eight rivets |
| 5 | Reaper | 2,500 | + three ring spikes: bottom and both sides |
| 6 | Soul Harvester | 5,000 | + five spikes, the fel-lit inner rim and fel light on the shard's lower edges |
| 7 | Soul Tyrant | 10,000 | + the fel bolts crackling off the shard; eight spikes, evenly round the ring |
| 8 | Lord of Souls | 25,000 | + the arcs across the shard's face, the outer fel aura, and the top three spikes drawn taller as a crown |

(Emblem column added after 1.2.4: rank emblems.) Each rank builds on
the one below it. **[user]** A new rank needs a new `art/rank<N>.tga`;
`spec/Art_spec.lua` enforces it. **[call]**

(Raised when repeat claims began to score, 6.1: a raider claiming every boss
each week can earn over 1,000 points a week. **[call]**)

- Nothing is saved: the rank is worked out from the score (`Ranks.lua`), so
  existing characters get theirs at once and a friend's rank comes from the
  score they already send.
- Shown on the Me tab (5.8), on a friend's lines in the Friends tab ("Rank"),
  and in the login line.
- A claim that crosses a threshold prints "Rank up: you are now <rank> (rank
  N of 8)." in your own chat, shows a second popup, "RANK UP" (6.2), and from Reaper on goes to guild chat (6.4).

## 7. Settings

`/souldex` opens the window. `/souldex options` (and a small gear in the
window) opens settings. `/souldex add <name>` and `/souldex remove <name>`
manage the Friends list by name; any other word prints the command list.

(changed after 1.3.0: a review of the comforts players expect from an addon.
**[user: "QOL things that most modern and well developed addons have"]**; the
choice of which is the builder's. **[call]**)

- `/souldex find <text>` looks a soul up by name: every mob, player and raid
  creature in your dex whose name contains the text (any case, at least 2
  letters), names starting with it first, up to 8 lines in your own chat:
  "Hogger ×12 · Elwynn Forest" (the zone it was claimed in most, "+N" for its
  other zones; a player's class; a raid creature's raid), then "...and N
  more."
- `/souldex scale <60-160>` sets the window's size in percent; `/souldex
  reset` puts the window back in the middle at 100% (5.1).
- `/souldex test` (and "Test popup" in the options) shows a sample new-soul
  popup, with the sound when that is on. Nothing is recorded.
- `/souldex version` prints the running version.
- A **key binding**, "Open or close SoulDex", under Options > Keybindings >
  AddOns > SoulDex (`Bindings.xml`). Unbound by default.
- SoulDex is in the game's **addon list by the minimap** (the addon
  compartment, through `## AddonCompartmentFunc` in the `.toc`), with the top
  rank's emblem as its icon: a click opens or closes the window, a right-click
  the options. Its tooltip shows the version, your rank and score.
- The settings are also a page of the game's own Settings window (Options >
  AddOns > SoulDex), with the same controls as the small panel; both stay in
  step. A client without that API keeps only the small panel.
- When another SoulDex user in your guild or group (or an added friend) runs
  a newer version, one chat line per session says so: "A newer SoulDex is
  out: v1.5.0. You have v1.4.0." A release player is never told about a beta;
  a beta player is told about newer betas and releases. An unbuilt copy
  ("dev") neither tells nor is told.

After each login or `/reload`, one chat line shows the addon is on:
"SoulDex v<version> loaded. <Rank>, <score> pts. Type /souldex or /dex to
open." **[user]** (the rank and score were added with the rebrand; they are
left out if the dex isn't loaded yet). The settings:

- New-soul popup on/off
- New-soul sound on/off
- Claim chatter in chat on/off, **off** by default: one line in your own chat
  frame for every claim, in the warlock's voice ("Hogger's soul is yours.
  That's 12.", with "(+N pts)" when it scored). `Flavour.chatter`. **[user]**
- Guild announcements on/off
- Login message in chat on/off, **on** by default (changed after 1.3.0): the
  "loaded" line above.
- Boss names after the fight (test) on/off, **off** by default (added after
  1.4.0-beta.1): the experiment described under "Naming souls in dungeons and
  raids".
- Window size, a sample popup and a window reset (above; not switches).

All saved.

## 7a. Code layout

(changed during build: the module list is owned by `CLAUDE.md`, not this
spec.) Notably the UI is split across `UI.lua` (window, tabs, panes),
`UIList.lua` (pooled scrolling list and the shared small button),
`UIFormat.lua` (text and colour helpers; rarity colours come from `Rarity.lua`) and `UIDetail.lua` (detail pane content), and the Friends network
glue and tab live in `Net.lua`.

(changed after 1.2.4: rank emblems.) `art/` holds the emblem textures
(`rank1.tga` to `rank8.tga`; shipped, generated, never hand-edited);
`scripts/art/` holds their source (`emblem.html`) and build (`render.sh`),
which are not shipped. `Ranks.emblem(index)` gives a rank's texture path, and
`Ranks.of(score).emblem` the one for a score. **[call]**

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
- Drain Soul a mob to death and get a shard: the popup "SOUL CLAIMED"
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

**Soul-name whisper** (in a dungeon; details in
`docs/superpowers/specs/2026-11-15-soul-name-whisper-design.md`)
- **Test this first:** Drain Soul a mob out of combat -> the popup shows its
  real name, with points, and no red "Interface action failed" error appears
  (the whisper is sent from a spell event, not a key press; this was never
  probed). No `SDX1:` line shows in chat in normal play (a reply that arrives
  as a secret value can't be filtered and may show; see Known limitations).
  If the send is blocked anyway, SoulDex prints "Soul names in dungeons are
  off for this session" once, the shard ends as an Unknown soul, and no more
  whispers go out until a `/reload`.
- Same mid-pull -> the popup comes within a few seconds (after combat at the
  latest).
- During a boss encounter -> the shard ends as an Unknown soul (chat is
  locked), and no "Interface action failed" error appears.
- Drain Soul with the mouse over a different mob -> Unknown soul, never the
  other mob's name.
- `/reload` within a few seconds of a drain -> that shard is an Unknown soul
  after the reload, counted once.
- After a drain in a dungeon, and again after its popup, `/r` still targets
  whoever last whispered you, not yourself.
- While a name is pending, hovering the shard shows the grey "Unknown soul"
  with "<zone> · name pending", then "Soul of <name>" once it arrives.

**Shard tooltip**
- Hover the new shard: the tooltip's top line reads "Soul of <name>" (name
  coloured) instead of "Soul Shard", the box is wide enough for it, and
  "<zone> · <date>" is the last line; an Unknown soul shard's top line is a grey
  "Unknown soul". Old or unmatched shards still say "Soul Shard" with no extra lines. Move the shard to another bag,
  sort the bags, put it in the bank and take it out, relog: the line stays on
  that exact shard.

**Window**
- Log in or `/reload`: one chat line "SoulDex v<version> loaded. <Rank>,
  <score> pts. Type /souldex or /dex to open.", the rank in fel green (with a version number such as "v1.1.0", not
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
- Milestones: each reads "<name> · <goal>"; earned ones have the name in fel green
  and a date, the rest are dimmed with progress and a thin green bar under
  the row. Crossing one prints "Milestone earned: <name> (<goal>)"; a guild message goes out only for the
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

**Comforts and fixes (after 1.3.0)** None of this has been seen in game.
- Fully restart the game (new files). No Lua errors at login.
- The addon list by the minimap has a SoulDex entry with the purple-and-green
  emblem. Hover: version, rank and score. Click: the window opens and closes.
  Right-click: the options panel. If there is no entry, report it.
- Options > Keybindings > AddOns has "SoulDex" with "Open or close SoulDex".
  Bind a key: it opens and closes the window. If the header reads
  `BINDING_HEADER_SOULDEX` or the entry is missing, report it.
- The game's Settings window (Esc > Options > AddOns) has a SoulDex page with
  six switches, "Window size" and two buttons. Tick one there: the small
  panel (`/souldex options`) shows the same, and the other way round. If the
  page is blank, misplaced or missing, report it (the small panel still works).
- Options: "+" and "-" grow and shrink the window by 10% between 60% and
  160%, the number between them follows, and the size survives `/reload`.
  `/souldex scale 130` does the same; `/souldex scale huge` explains itself.
- Drag the window to a corner, then "Reset window" (or `/souldex reset`): it
  is back in the middle at 100%.
- "Test popup" and `/souldex test`: the popup shows "ELITE SOUL CLAIMED",
  Hogger, "+5", with the sound when the sound switch is on. Nothing is added
  to the dex.
- Untick "Login message in chat", `/reload`: no "loaded" line. Tick it again.
- `/souldex find <part of a name you have>`: a heading and one line per soul
  with its count and zone. `/souldex find zzzz`: "No soul matching".
- `/souldex version` prints the version; hovering the gear shows "Options".
- Catching still works after the shard-map change: drain a mob, get the popup,
  the shard's tooltip names it; `/reload`, the tooltip still names it; move the
  shard to the bank and back, it still names it.
- In a dungeon: drain a mob, let the channel end, drain the **same** mob again
  and kill it. Its shard gets the name (before, it stayed unnamed).
- In a dungeon: press Drain Soul and Tab to another mob at once, before the
  channel bar appears. The soul should be an Unknown soul, never the second
  mob's name.
- Shadowburn one mob, start Drain Soul on another at once, let the first die:
  its shard is unnamed, not named after the second mob.
- With two characters on different versions in one guild or group: the older
  one prints "A newer SoulDex is out: ..." once, and not again that session.
- Friends, with a second player on this build: Browse dex on a large dex
  reads "Receiving X's dex... ~N min" with no "asking again" line, and opens
  when done. Close the window while it is on its way: it stays closed and one
  chat line says the dex arrived. With the other player on 1.3.0: browsing
  works as before, both ways.
- `/souldex add <a name that isn't online>`: the name appears in the left
  list at once ("Not heard from yet."), and its × removes it.
- Hover a Friends row so its × shows and wait a minute: the × stays.
- Clean up right after login in a guild: either it removes only people
  outside the guild and group, or it says nobody was removed; pressed again a
  moment later it works. No guild member disappears from the list.
- Me tab, "Latest": a soul claimed this afternoon still reads "today" in the
  evening.
- (after 1.4.0-beta.1) In a listed raid, drain a trash mob out of a boss
  fight: after the popup, the Raids tab shows it claimed in that raid's list,
  not under Mobs > Raids.
- (after 1.4.0-beta.1) Experimental, in a dungeon with a boss that starts an
  encounter (Arcanist Doan in the Scarlet Monastery Library did): tick "Boss
  names after the fight (test)". Drain the boss so it dies during your
  channel, and **keep it targeted** until a few seconds after it dies. Expected:
  no red "Interface action failed" error, the shard's tooltip reads "name
  pending" for a moment, then the popup names the boss. If instead the soul is
  Unknown, or the chat line "Soul names in dungeons are off for this session"
  appears, report which. Then once more, but press Tab right after the boss
  dies: the soul should be Unknown, never another mob's name.
- (after 1.4.0-beta.1) While a second player browses your dex, nothing shows
  in your chat; if they log off while it is still sending, still nothing (no
  "No player named ..." lines).

**Raid data**
- In a raid, `/dump UnitGUID("target")` on a mob: the sixth dash-separated
  field of the GUID is the NPC ID and must match that mob's id in
  `src/RaidData.lua`. Check at least one boss and one trash mob.

**Forever raids** (added after 1.2.4)
- Raids tab: The Barrow Deeps and Hyjal Summit are the top two rows, each
  reading `TBD`; clicking one shows "Roster still sealed: 8 bosses wait
  inside. Every soul you claim here is kept." (13 for Hyjal Summit). The Me
  tile still reads "N / 7" and Milestones has no "The Barrow Deeps Drained".
- From 2026-12-09, inside each raid: `/dump GetInstanceInfo()`. The first
  value must be the raid's name as listed, the second `"raid"`; write down
  the eighth (the instance ID).
- Claim a soul there: the popup shows, the soul is listed under that raid in
  the Raids tab (not under Mobs), and the row reads `1 / ?`. After `/reload`
  it is still there.
- For each boss and a few trash mobs, `/dump UnitGUID("target")`: write down
  the name and the sixth dash-separated field. Also write down the names of
  the raid's boss achievements. These fill `src/ForeverData.lua`.

**Me tab**
- Me is the left-most of six tabs and all fit in the window. On top is your
  rank in fel green with the score in white, then "Rank N · next: <rank>" with
  "<points> pts to go" and a thin green bar under it showing how far along you
  are. Below, without needing to scroll: Unique mobs, Players, Raids
  completed, Souls taken, Zones visited, Most claimed,
  Top zone, (Unknown souls only if you have any) and Friends rank ("#2 of 3", or
  a dash with no friends seen). A new catch updates it while open; browsing a
  friend shows their rank and numbers without a Friends rank.

**UI rework (after 1.2.4)** Everything here is drawn blind; report anything
that overlaps, is cut off, or shows as a solid green square (a missing icon).
- Window: larger than before, lighter purple at the top shading to near-black
  at the bottom (a flat colour is acceptable; say which you see). The rank
  emblem sits at the left of the title. Right of the title: your rank in
  green in a small box, then the total and score, the gear and ×. None of
  these overlap, including on the Milestones tab and while browsing a friend
  ("« My dex" button, "SoulDex · Viewing X").
- Under the title a thin line is green from the left as far as your progress
  to the next rank.
- The active tab has a green underline; the selected zone, class or raid has
  a green mark on its left edge; each soul's row has a thin stripe on its left
  (gold for elites, silver rares, orange bosses).
- Click a mob: the card slides in. Check the tinted header, the icon (right
  for a beast, humanoid, undead, demon, elemental; the rank emblem otherwise),
  name, the line under it, the points badge at the top right, the flavour
  line with a bar beside it, the row of eight stars with "N / M to next
  star" and a bar, the four boxes (Claimed, First, Where, Last) with their
  values readable, and "« Back" at the bottom right. A raid boss and a rare
  have no star row. A player shows crossed swords, Sharded / Guild / First /
  Last, and their places below.
- Me: rank emblem, rank, "RANK N OF 8", score, bar and "N pts to <rank>" on the
  left; six boxes with a number over a small label; under them RECORDS with
  Most claimed, Nemesis, Hunting ground, Rarest trophy, Latest ("today"),
  Best day (a dash until your first claim after updating) and Zones hunted.
- Milestones: MOBS / PLAYERS / RAIDS headers with "N of M"; unearned ones
  first with bars; clicking "N earned" shows and hides the earned ones.
- Popup: a coloured bar at its left edge, the points large on the right
  ("+5" over "PTS"), and a band of light that crosses once. Ranking up shows
  a second popup just under it with "RANK UP" and plays a different sound; a
  boss plays a different sound too. Neither popup overlaps the other.
- Options has four boxes; ticking "Claim chatter in chat" prints one line per
  claim, and unticking stops it.

**Rank emblems (after 1.2.4)**
- Quit the game fully and start it again before these checks: the client
  only picks up newly added addon files at a full restart, and `/reload` does
  not load new texture files.
- The title bar, the Me crest and both popups show the emblem: no green
  square, not upside down, not mirrored, no dark or coloured box round it.
- The card of a mob with no known type shows the emblem whole, not cropped,
  on a dark square with the soul-coloured border.
- `/souldex` on a low and a high character (or a friend's dex): the emblem
  differs by rank, and the title-bar one changes while browsing a friend.
- Ranking up: both popups show the new rank's emblem.
- The 14 px title-bar emblem is recognisable.
- If every emblem is still a green square after a full restart, the client
  does not read this TGA form: report it.

**Rebrand (after 1.2.4)**
- The popup's title and border follow the soul: purple "SOUL CLAIMED" for an
  ordinary mob, gold "ELITE SOUL CLAIMED" for an elite, silver for a rare,
  orange "BOSS SOUL CLAIMED" for a boss, the class colour and "PLAYER SOUL
  CLAIMED" for a player. The name line no longer ends in "(Elite)".
- Rank up: on a low character, claim souls until the score passes 50. That
  claim shows a second popup, "RANK UP" and "Acolyte" in fel green, and chat
  shows "Rank up: you are now Acolyte (rank 2 of 8)." No guild message below
  Reaper (2,500 points).
- Progress bars: an unfinished raid in the Raids list, each unearned
  milestone and the Me tab's second line have a 2 px green bar along the
  bottom of the row, as wide as the progress; no bar on a finished raid or an
  earned milestone, and no stray bars on other rows after switching tabs or
  scrolling. **Please check** the bars sit inside the row and don't overlap
  the text.
- Friends: clicking a person shows a fel-green "Rank" line above their score.
- Mastery: claim the same ordinary mob 10 times. The 10th claim shows the
  popup "MASTERY: 1 STAR" in fel green with "<zone> · ×10 claimed" and "+1"
  (+2 for an elite) and chat says "Mastery: <name> reached 1 star (+1 pts).".
  Its row then reads "1★ ×10" with a small **green** star (**please check**
  the star is green, not yellow, and sits on the text line), and its details
  have a "Mastery" line "1★ · 10/25" with a bar. The Me tab's "Mastery stars"
  goes up by one. A mob you had already claimed 10 or more times before
  updating shows its stars at once, and the score is higher than before.
- Raid boss: claim a boss you already have. The score rises by 25 again; no
  popup (it isn't new and bosses earn no stars).
- Player: claim a player you already have on a later day: +3 points, once.
  Claim them again the same day: nothing. A rare works the same with +2.
- Options: the first two boxes read "New-soul popup" and "New-soul sound".
- An empty Mobs tab reads "No souls claimed yet. Go drain something." on one
  or two lines, not cut off.

**Friends** (two players A and B on a packaged build, same realm)
- Same guild: within about 5 s of login the Friends tab on both lists both
  names by score, you in your ranked place marked "(you)". Alone, your row is
  hidden, the left side shows the help text ("Guild and group members with SoulDex appear here." and "/souldex add <name>") and the right side is empty.
- Click the other person: Rank, Score, Unique mobs, Players, Raids completed, online.
- A clicks Browse dex: "Asking B..." then B's dex fills every tab, the title
  reads "SoulDex · Viewing B" with a "« My dex" button, and entries B has and
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

### Naming souls in dungeons and raids: where it stands and what to try next

**[user: "I want dungeons and raids to allow us to capture where the soul is
coming from ... note the limitations but keep thinking about how we can solve
and investigate"]** (added after 1.4.0-beta.1.)

What the game hides, and where. Inside instances the client applies a "Map"
addon restriction: `UnitName`, `UnitGUID`, `UnitCreatureID`,
`UnitCreatureType`/`Family` and the `UNIT_DIED` / `PARTY_KILL` event GUIDs are
secret for every unit, in and out of combat (the client's own API docs mark
them `SecretWhenUnitIdentityRestricted`; build 1.60.1 (70938), branch
`forever` of Gethe/wow-ui-source). During a boss encounter chat is locked as
well, which stops the self-whisper.

What works today:
- Dungeon and raid trash, and bosses drained **before or after** their
  encounter: named by the self-whisper (4.2).
- A raid soul named that way fills its raid slot by name (above).

What does not, yet:
1. **A boss that dies during its encounter** is an Unknown soul (chat locked,
   so no whisper).
2. **A creature a raid doesn't list, or any raid creature on a non-English
   client,** is filed as a plain mob under Mobs > Raids.
3. **Creature type and family** are missing for souls only ever claimed in
   instances.
4. The target must be the **target** at the cast: mouseover, focus and
   click-cast casts on a hidden name stay Unknown.

Leads, most promising first. None is built; each needs the probe
(`scripts/probe/SoulDexProbe`, `/sdprobe`) to say whether the client allows it.
The rule stands: a lead that could give a wrong name is not used.

| # | Lead | Would solve | What must be true (probe) |
|---|---|---|---|
| A | Ask late: keep the boss's shard held through the encounter and send the whisper when the chat lock lifts (`ENCOUNTER_END`, `ADDON_RESTRICTION_STATE_CHANGED`), if the target hasn't changed since the cast (the target-change count already exists). **Built as an experiment, off by default** (the "Boss names after the fight (test)" option; below). | 1 | `%t` still expands to a **dead** target's name, and the send is allowed right after the encounter ends. The probe sends `SDXP:ENCOUNTER_END+0/+1/+3:%t` and logs the replies. |
| B | `BOSS_KILL` / `ENCOUNTER_END` carry `encounterID` and `encounterName`, and the docs do not mark them secret. A shard gained from a capture on a boss-classified target while that encounter runs could take the name the raid lists for that encounter. | 1 | The payload is readable inside the instance. Needs a table from encounter name to boss (the encounter is "The Four Horsemen", the soul is one horseman), so only encounters whose name is a listed boss can be used; dungeons have no list yet. |
| C | `CHAT_MSG_COMBAT_XP_GAIN` ("<name> dies, you gain N experience") names what died at the moment of the kill. | 1, 4 (while levelling only) | The text is readable in an instance and during an encounter. No use at level cap, and with a group kill of two mobs in one moment the names can't be told apart. |
| D | `C_Secrets.ShouldUnitIdentityBeSecret(unit)` says beforehand whether a unit's identity is hidden. | Cleaner guard, nothing new named | It answers readably. Would replace reading the name to find out. |
| E | The target's tooltip (`C_TooltipInfo.GetUnit`, `GameTooltip` text) or nameplate text. | 1, 3 | Almost certainly secret too (text carries the same restriction); logged by `/sdprobe target` to be sure. |
| F | Boss yells and emotes (`CHAT_MSG_MONSTER_YELL`, `CHAT_MSG_RAID_BOSS_EMOTE`) carry the speaker's name. | 1, weakly | Readable during the encounter. Only tells who spoke, not who died: could only confirm a name from B. |
| G | Localised raid lists, or a list of names per NPC id per language. | 2 | No probe: a data job (Questie ships localised names). |
| H | **Context clues [user: "find context clues from what's around the player, maybe via scanning"].** Comparing units needs no names: `UnitIsUnit("target", "boss1")` may say "the target is this encounter's boss" where the name is hidden. With B's encounter name, and only one boss unit present, that names the boss without the whisper and without keeping it targeted. | 1 | The boss units (`boss1`..`boss5`) exist in this client's dungeons and raids, the comparison is readable during the encounter, and the encounter's name is the boss's (table I). The probe's `scene:` line logs all of it at `ENCOUNTER_START`, at the kill and when a shard arrives. |
| I | **A small boss table [user]**: per instance, each encounter's id and name, the boss (or bosses) it stands for, and where it is (subzone text). It turns B and H into names safely: an encounter is used only when the table says it has exactly one boss and gives that boss's name ("Ring of Law" and "The Four Horsemen" are in it as "no single boss": never named this way). The subzone is a second check, and a fallback clue where there are no encounter events. | 1, and dungeon bosses for a future Dungeons list | Filled from what the probe logs (encounter ids and names, subzones), not from memory: a wrong row would be a wrong name. For raids the boss names already ship in `RaidData`. |

Order of work: probe a dungeon boss first (it decides A, B, C, H at once);
A is already in the build to try; then the boss table (I) from the logged
encounters, which unlocks B and H. Whatever names a soul, the rule holds: two
clues that disagree, or one clue that could mean two creatures, give an
Unknown soul.

**Boss names after the fight (experimental; lead A).** A switch in the options,
**off** by default, `settings.lateAsk`. With it on, a Drain Soul or Shadowburn
on a hidden-name target while chat is locked (a boss encounter) no longer
gives up on the name: when everything else about the ask is right
(`Whisper.shouldDefer`), the ask is held, and its shard is held like any
whisper-named shard ("name pending"). Every second, and when the encounter or
a restriction ends, each held ask is looked at again (`Whisper.lateStep`): it
is sent the moment chat is unlocked and the player is not AFK or DND, if the
target has not changed since the cast; any target change, or no target,
fails it at once (an Unknown soul, as today). A recast on the same target
replaces the held ask, so a long fight ends in one whisper. A held ask never
sends into a chat lock. The usual limits apply (60 s of unrestricted time, at
most 600 s). It is off by default because it has never run in game: if the
client refuses the send it shows a red error and turns soul names off for the
session (4.2). What it cannot do: name a boss you stopped targeting before
the fight ended.

Probe run to do (adds to section 9): install `scripts/probe/SoulDexProbe` as its
own addon, then in a dungeon:
- target a mob and type `/sdprobe target` out of combat and mid-pull;
- kill a boss with it targeted and leave it targeted for 5 s after it dies;
- loot it; then `/reload` and send the `SoulDexProbeLog` from
  `WTF/Account/<account>/SavedVariables/SoulDexProbe.lua`.
The lines that decide the leads: `ENCOUNTER_START`, `BOSS_KILL`,
`ENCOUNTER_END` (are the names readable?), the three `ask(...)` lines and their
`reply:` lines (does a late ask name the dead boss?), `CHAT_MSG_COMBAT_XP_GAIN`
(is the text readable?), and `idSecret=` / `names(target)` on the target lines.

### Known limitations

- Newcomer replies can be sent needlessly near the 6-minute mark (the newcomer
  threshold is only one poll tick above the 300 s heartbeat).
- Added friends who are offline are asked every 60 s with no back-off (their
  "not playing" notices are hidden).
- Alt-Z (hiding the UI) resets browsing to your own dex.
- A browsed friend's Milestones tab shows nothing earned (no dates are sent).
- Raid data is Classic Era and may need regenerating for WoW: Forever content.
- A TBD raid's instance ID is learned from its English name: on another
  client language those claims go under Mobs > Raids until the ID ships in
  the data.
- A boss claimed in a TBD raid scores by its classification, not the raid
  boss 25, until it is listed.
- A friend's souls from a TBD raid show only once your own client has learned
  that raid's instance ID.
- WoW: Forever can hide target names (secret values): SoulDex asks for them
  with a self-whisper; when it can't ask or no name comes back, the catch is
  counted as an "Unknown soul" per zone.
- A raid creature named by whisper has no NPC ID. (changed after
  1.4.0-beta.1.) Its name is looked up in that raid's list (`Raids.idByName`,
  exact name, never a name the raid lists twice), so it fills its slot and
  counts toward Raid Reaper. Still under Mobs > Raids: a creature the raid
  doesn't list, and every raid creature on a client in another language (the
  lists are English).
- A whisper reply that arrives as a secret value can't be checked by the chat
  filter and may show its `SDX1:` line in chat (not seen in testing).
- Bosses killed during their encounter stay Unknown souls: chat is locked
  then, and sending anyway shows a red "Interface action failed" error, so
  SoulDex never sends.
- Sending the whisper from a spell event (no key press) was never tested in
  game. If the game blocks it, soul names in dungeons stay off for the rest
  of that session (one chat line says so) and those souls are Unknown.
- Casts through other macro targets (`@targettarget`, `@party1target`,
  unit-frame click-casting) pass the whisper guard and can be misnamed.
  **[user accepted]**
- Chat addons that read whispers themselves (WIM, Prat, ElvUI) may show
  `SDX1:` lines.
- Creature type and family are missing for souls only ever caught in
  dungeons; an open-world catch of the same creature fills them in.
- Shadowburn catches are untested in game.
- WoW: Forever beta bug: SavedVariables can fail to load after a reload.
- A Shadowburn and a Drain Soul on two different mobs within the Shadowburn's
  8 s leave the next shard unnamed (both captures are live).
- Changing target between pressing Drain Soul or Shadowburn and the cast
  landing, on a mob whose name is hidden, makes that soul Unknown (the whisper
  is not sent).
- With more than 400 named shards out of the bags (banked or mailed), the
  ones seen longest ago lose their tooltip name at the next login.
- A whisper-named player whose `UnitIsPlayer` answer was unreadable is filed
  as a mob, and a player claimed once with and once without a readable realm
  is two entries. **[accepted for now: neither has been seen; a fix would turn
  every dungeon soul Unknown if the answer were unreadable there]**
- A shard refunded by a demon that despawns during a Drain Soul (or within
  3 s after it) would take the drain target's name, and the real shard from
  the kill then stays unnamed.
- A shard gained while the bank, mailbox, trade or vendor window is open or an
  item is on the cursor, or while any bag slot is unreadable (this scan or the
  previous one), is never named; nor is a kill shard that arrives in the same
  bag scan as another new shard.
- Anyone, not only friends or guild members, can whisper a request for your
  dex and get it (one at a time, 10 s apart), which includes the list of
  players you have sharded. Limiting it to people you know would stop someone
  who added you by name from browsing your dex unless you add them back.
  **[user: "I'm okay with people requesting for now ... so long as it doesn't
  create chatter clutter for the person receiving the messages"]** It makes no
  chat line on your side: the request and the dex are hidden addon messages,
  and the "No player named ..." lines the game prints when the asker logs off
  mid-transfer are hidden for as long as pieces are still going out (changed
  after 1.4.0-beta.1: they were hidden for the first 5 s only).
- Clean up uses the guild roster the game has cached; if it is stale, a guild
  member may be removed and comes back on their next score update.
- A Drain Soul started within 3 s after another one ended on a different
  target, with no shard from the first, leaves the next shard unnamed.
