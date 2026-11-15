# Soul names through a self-whisper — design

Date: 2026-11-15. Owner document for SoulDex as a whole stays
`2026-11-10-souldex-design.md`; once this is built, its sections 4 (Catching),
6 (Game layer) and 9 (in-game checks) take the parts below, and this file is
the record of how the decision was made.

## 1. Intent and why

Inside dungeons, WoW: Forever hides your target from addons. Measured in game
in Scarlet Monastery (2026-11-15, `/dex testtarget`, in and out of combat):

| Value | Inside SM |
|---|---|
| `UnitName("target")` | secret |
| `UnitGUID("target")` | secret |
| `UnitLevel`, `UnitIsPlayer` | readable |
| `GetInstanceInfo` | readable |

So every dungeon catch becomes an Unknown soul today: no name, no points, no
popup. A run of SM gave 11 Unknown souls and no popups, which looks broken to
the player.

The game itself can still see the name: chat expands `%t` to your target's
name before sending. A whisper to yourself of `<marker>:%t` comes back as a
normal chat line with the name in plain text. Another addon (Shard Source
2.0.3, by Blueteak) does this on the same client. We build our own version
from scratch; no code is copied.

**[user]** "I want to build our own version from scratch." Approach A
(hold the shard until the name arrives) was picked by the user.

## 2. Goals, non-goals, anti-goals

Goals
- Dungeon catches (and any other hidden-name catch) get their real name,
  points, popup, sound, rank-up and milestones, like an open-world catch.
- The player never sees the marker whispers in chat.

Non-goals
- Recovering souls already saved as Unknown (no capture data to ask with).
- Players' names in instanced PvP (same mechanism may work; not a target).
- Reading names from Shard Source's saved data.

Anti-goals (a failure even if names come through)
- **Recording a wrong name.** A name that might belong to another creature
  records nothing better than Unknown. (Project rule: never record a wrong
  name.)
- Visible chat spam, or any message reaching anyone but the player.
- A dex that has to be corrected after the fact (counts going down).

## 3. Constraints

- Lua 5.1, Interface 16001; every API value checked with `issecretvalue`
  (`Capture.readable`/`plainString`); no combat log.
- Pure logic in pure modules with busted tests through `LoadAddonFile`; WoW
  calls stay in `Capture.lua` (or a new game-facing file).
- **CLAUDE.md rule change needed:** "Messages go to the player's own chat
  frame only, never to a chat channel, except guild announcements." This adds
  a second exception: hidden marker whispers sent to the player themself.
  The spec's section 3 constraint and CLAUDE.md's Code rules both change.
- Chat sends can be blocked (`C_ChatInfo.InChatMessagingLockdown`, boss
  encounters). The addon already detects this (`chatLocked` in Capture.lua).
- In a dungeon the creature's GUID is hidden too, so there is no NPC id:
  only the name comes back. Level, classification, creature type and family
  are read separately at the same moment (to be confirmed readable, see 8).

## 4. Approaches

- **A. Hold the shard until the name arrives (picked).** A shard whose
  capture is waiting for a name is parked, not recorded. Reply → record the
  real catch then (popup and all, possibly seconds late). Timeout → record
  Unknown, as today. One record per shard; no corrections.
- **B. Record Unknown now, upgrade later.** Instant popup, but the dex must
  take the Unknown back and add the real catch: two popups for one shard and
  counts that can drift. Rejected.
- **C. Borrow Shard Source's names** (same item-GUID key). Only helps players
  running both addons; user wants our own. Rejected.

## 5. Design

### 5.1 When to ask

At the moments SoulDex already reads the target (Drain Soul
`UNIT_SPELLCAST_CHANNEL_START`, Shadowburn `UNIT_SPELLCAST_SUCCEEDED`, via
`targetInfo`), if the read comes back unknown **because the name is secret**
(not because of a name mismatch), the capture is opened as *pending a name*
and one whisper is sent:

    SDX1:<token>:%t     to the player's own full name, "WHISPER"

- `<token>`: a short id, mapped to the capture: lowercase hex of the send
  time (`GetTime()` in ms, low 20 bits) followed by a per-session counter, so
  a reply to a whisper sent before a `/reload` can't match a new token (the
  counter restarts, the time doesn't). Never contains `:`.
- One whisper per capture, never retried against a different target.
- Not sent when chat is locked down, when the guard in 5.2 fails, or when no
  chat filter could be installed (5.3; the lines would show): the capture
  stays plain Unknown, as today.
- Safety net (sending from an event handler was never probed): if
  `ADDON_ACTION_BLOCKED` / `ADDON_ACTION_FORBIDDEN` fires with arg 1 equal to
  the addon's name (arg 2 can read `UNKNOWN()`, so it isn't checked), no more
  whispers are sent that session, every waiting whisper fails at once, and
  one chat line says soul names are off for the session.
- The readable details (level, classification, creature type, family,
  isPlayer) are read at the same moment and kept on the capture.

### 5.2 Guard against a wrong name

`%t` is the player's **current target**. If the spell went somewhere else
(mouseover or focus macro), `%t` names the wrong creature. The current code
rejects that case by comparing the SENT event's target name with the
target's, which is impossible when both are secret.

Rule: only ask when the spell's target can be shown to be the current target.
Ask only if, at the moment the whisper is sent (channel start / Shadowburn
success, the same handler, so `%t` and the check see the same target), there
is a target and neither `mouseover` nor `focus` is a different unit from
`target` (`UnitIsUnit`, each value checked; anything unreadable or unknown →
don't ask). Also never ask when the cast's SENT event named a readable unit
while the target's name is secret: the spell went somewhere else. A normal Drain Soul cast with the
mouse resting on another mob therefore stays Unknown. That's the price of
never recording a wrong name.

**[user]** Accepted leftover risk: casts through other macro targets
(`@targettarget`, `@party1target`, unit-frame click-casting) pass this
guard and could name the wrong creature. Documented as a known limitation.

### 5.2a No macros

**[user]** "I don't want to burden users with macros." Whispers are sent
only by the addon, as Shard Source does; the player sets nothing up. When the
client refuses the send (chat lockdown, boss encounter) that capture stays an
Unknown soul. Macros were considered (a key-press whisper gets past addon
chat restrictions and pins `%t` to the cast's unit) and dropped.

### 5.3 Receiving the reply

- Listen to `CHAT_MSG_WHISPER`. A line counts only if its text matches
  `^SDX1:<token>:(.+)$`, the token is pending, and the sender is the player
  (sender GUID equals `UnitGUID("player")`, both readable).
- If the event's text or sender is secret (combat restriction), keep the
  line id (if readable) and re-read the line from chat history
  (`C_ChatInfo.GetChatLineText` / `GetChatLineSenderGUID`) when restrictions
  lift: `PLAYER_REGEN_ENABLED`, `ADDON_RESTRICTION_STATE_CHANGED`,
  `ENCOUNTER_END`, zone change. Line ids are kept up to the timeout.
- A reply whose name is empty, still contains `%t`, or contains `|`, `:`,
  newlines, or is longer than a creature name can be, counts as failed.
- **[my call]** Not sent while the player is AFK or DND (the auto-reply would
  show a line the filters don't cover; values checked, unreadable → don't
  send). After sending, the last-tell target (`/r`) is put back to what it
  was, if the client exposes it, and again when the reply arrives or the wait
  ends if it then points at the player (the incoming reply can set it; a
  friend who whispered meanwhile keeps it). Chat addons that read
  `CHAT_MSG_WHISPER` themselves (WIM, Prat, ElvUI) may still show the line: a documented known
  gap, not handled.
- Chat filters (`ChatFrame_AddMessageEventFilter` or the newer
  `ChatFrameUtil.AddMessageEventFilter`) hide `CHAT_MSG_WHISPER` and
  `CHAT_MSG_WHISPER_INFORM` lines starting `SDX1:` sent by/to the player, for
  the whole session (late echoes included). No filter API, no whisper. A line
  whose text arrives as a secret value can't be checked and stays shown
  (known limitation; not seen in testing).

### 5.4 Holding the shard

- When a new shard is matched to a pending capture, it is stored in the shard
  map as **pending**: `{ soul = false, pending = <token>, seen = now }`. No dex
  record, no popup yet. Its tooltip shows the grey "Unknown soul" for now
  (tooltip text: builder's call).
- Name arrives (before or after the shard): build `info` from the capture's
  readable details plus the name, run the normal `Capture.record` path, fill
  the shard's soul, then `afterCatch` (popup, sound, rank-up, announcements).
  A reply that lands before the shard waits on the capture; the shard records
  straight away when it appears.
- Timeout, or failure: record Unknown exactly as today (`recordUnknown`,
  Unknown soul on the shard). **[my call]** The timeout is **60 s of
  unrestricted time**: the clock only runs while the player is out of combat
  and chat isn't locked down, so a long pull never times a reply out before
  it can be re-read. Hard ceiling: **10 minutes** after the whisper, whatever
  the state. Line ids from 5.3 are kept for the same span.
- **[my call]** If classification, creature type or family are unreadable,
  the name is still recorded with those fields missing (points as a normal
  mob). `Dex` gains a small change: a later catch of the same creature fills
  any missing field, and if that raises its rarity, its points are topped up
  (the top-up counts toward a rank-up).
  Points only ever go up, so nothing is "taken back". If the probe in 8.6
  shows these are readable in dungeons, this branch is just a safety net.
- Raids: with no NPC id, a raid catch named by whisper is recorded as a mob
  in "Raids", like a raid SoulDex doesn't list. Matching raid bosses by name
  is out of scope (builder may note it as a follow-up).

### 5.5 Reload and logout

Pending tokens live in memory only. A shard still pending at `/reload` or
logout: on the next login its token is gone, so it is resolved to Unknown
(recorded via `recordUnknown` once, with the zone saved on the pending entry).
The pending entry must therefore save the zone and time it was caught in.
**[my call]** Not worth saving tokens: a reply can't be re-read across a
reload anyway.

### 5.6 Where the code goes

- Pure (new `src/Whisper.lua`, with `spec/Whisper_spec.lua`): token creation,
  message building, reply parsing and validation, the pending table with
  timeouts (time passed in), and the "should I ask" decision from plain
  inputs.
- Pure changes: `Catch.lua` (capture carries `pending`/readable details),
  `Shards.lua` (pending entries; resolving them).
- Game: `Capture.lua` wires sending, the whisper event, history re-reads, the
  chat filter, and the restriction-lift events. New WoW APIs go in
  `.luacheckrc` `read_globals`. `SoulDex.toc` lists `src\Whisper.lua` above
  `src\Init.lua` (this release needs a full restart; say so in the release
  intro).

### 5.7 Settings

**[my call]** No new option. It only runs when a name is hidden, and the
whispers never show. (If the user wants an off switch, it slots into the
existing options list.)

## 6. Left to the builder

- Token format details, the exact validation length limit, the tooltip text
  for a pending shard.
- Whether the pending table lives in `Whisper.lua` or on the capture window.
- How the debug commands from branch `debug/testpopup` are reused for testing
  (that branch is local and must not be pushed).

## 7. Testing

- busted: reply parsing (good, `%t` unexpanded, wrong token, injected `|`/`:`),
  the ask decision for every guard input, pending → resolved, pending →
  timeout → Unknown, reply before shard, shard before reply, pending at login
  → Unknown once, two captures with two tokens.
- `luacheck .` clean.

## 7a. Probe results (2026-11-15, Scarlet Monastery, `/sdprobe`)

| Read | Out of combat | Mid-pull |
|---|---|---|
| `UnitIsUnit("mouseover"/"focus","target")`, `UnitExists` | readable | readable |
| `UnitClassification("target")` | readable (`elite`) | readable |
| `UnitCreatureType` / `UnitCreatureFamily` | secret | secret |
| `UnitIsAFK`/`UnitIsDND`, `InChatMessagingLockdown`, `InCombatLockdown`, `IsEncounterInProgress` | readable | readable |
| `GetUnitName("player", true)` | `"Forgot Shards"` (two-part name, space) | same |
| `SendChatMessage("SDXP:%t","WHISPER",nil,me)` | sent | sent |
| `CHAT_MSG_WHISPER` text / line id (arg 11) / sender GUID (arg 12) | all readable, `%t` expanded | all readable |
| `ChatFrameUtil.AddMessageEventFilter`, `ChatFrame_AddMessageEventFilter`, `ChatEdit_Get/SetLastTellTarget`, `C_ChatInfo.GetChatLineText` | present | — |

Boss encounter (Arcanist Doan, SM Library): before the pull everything as
above (reply `SDXP:Arcanist Doan`). During the encounter:
`InChatMessagingLockdown` = true, `IsEncounterInProgress` = true,
`UnitIsAFK`/`UnitIsDND` = secret. Sending anyway did **not** raise in `pcall`;
the client blocked it with `ADDON_ACTION_BLOCKED` and showed the red
"Interface action failed because of an AddOn" error. So the lockdown check
before sending is required (not just tidy): a send during lockdown is a visible
error, never a name.

So: the 5.2 guard works; the whisper recipient is `GetUnitName("player", true)`;
creature type and family are recorded missing in dungeons and filled later
(5.4). **Bosses killed during their encounter stay Unknown souls** (known
limitation): the name can't be asked for while chat is locked.

## 8. In game (adds to spec section 9)

1. **First:** in a dungeon, Drain Soul a mob out of combat → popup with its
   real name, and no red "Interface action failed" error (the send comes from
   a spell event, not a key press; never probed). No `SDX1:` line in chat in
   normal play (a reply arriving as a secret value may show).
2. Same mid-pull → popup within a few seconds (after combat at the latest).
3. During a boss encounter → shard ends as Unknown soul (chat locked), no
   error.
4. Drain Soul with the mouse over a different mob → Unknown soul, never the
   other mob's name.
5. `/reload` within a few seconds of a drain → that shard is an Unknown soul
   after reload, counted once.
6. **Open questions only the client can answer, checked first with a quick
   probe:** can the whisper be sent mid-combat in a dungeon; is `UnitIsUnit`
   readable there; are `UnitClassification`/`UnitCreatureType` readable there.
   If sending mid-combat is blocked, the feature still names drains whose
   whisper could be sent (out of combat) and leaves the rest Unknown; if
   `UnitIsUnit` is unreadable, 5.2 needs rethinking before building.
