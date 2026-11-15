# Soul Names Through a Self-Whisper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Name Drain Soul / Shadowburn catches whose target name the client hides (dungeons) by whispering `SDX1:<token>:%t` to the player and holding the shard until the expanded name comes back.

**Architecture:** A new pure module `src/Whisper.lua` owns the marker format, reply parsing, the "should I ask" decision and the pending-request queue with its restriction-aware timeout. `Shards.lua` learns pending shard entries, `Dex.lua` learns to fill missing details on later catches, and `Capture.lua` wires sending, receiving (event + chat-history re-read), the chat filter, and resolving parked shards.

**Tech Stack:** Lua 5.1, WoW: Forever Interface 16001, busted, luacheck.

**Spec:** `docs/superpowers/specs/2026-11-15-soul-name-whisper-design.md` (decision record). Owning spec: `docs/superpowers/specs/2026-11-10-souldex-design.md`.

## Global Constraints

- Branch `feat/soul-name-whisper`; never push or tag unless the user asks. Agents on another machine push to `main`.
- Every file starts `local _, ns = ...`; no new globals except those in `.luacheckrc` `globals`.
- Pure modules call no WoW API; tested through `LoadAddonFile`. Game wiring tested in `spec/Capture_spec.lua` with its stubbed globals.
- Every API value checked with `issecretvalue` (`Capture.readable` / `plainString` / `plainNumber`). Unreadable means "don't": don't ask, don't trust.
- Never record a wrong name. A shard with no name ends as an Unknown soul, recorded once.
- Marker: `SDX1:`. Message: `SDX1:<token>:%t`, channel `"WHISPER"`, to the player's own full name.
- Timeout: 60 s of **unrestricted** time (out of combat and chat not locked); ceiling 600 s after sending, whatever the state.
- No new setting. No macros.
- New WoW APIs go in `.luacheckrc` `read_globals`. `src\Whisper.lua` goes in `SoulDex.toc` directly after `src\Catch.lua` (so above `src\Capture.lua` and `src\Init.lua`).
- `luacheck .` and `busted` pass before every commit (Windows: `cmd //c "%APPDATA%\luarocks\bin\luacheck.bat" .` and `busted.bat` from Git Bash).
- Tabs for indentation.

## Review Focus

1. **Reply arrives before the shard** (fast kill, shard bag update lags): the shard must record named straight away, not park forever. Test in Task 6.
2. **Reply arrives secret in combat and is re-read only at `PLAYER_REGEN_ENABLED` after > 60 s of combat**: still named, because the clock paused. Test in Task 2 and Task 6.
3. **Two Drain Souls in a row on two hidden targets**: each reply resolves its own capture by token; a reply for an expired token does nothing. Test in Task 6.
4. **`/reload` with a parked shard**: recorded as exactly one Unknown soul in the zone it was caught in, and the entry is no longer pending. Test in Task 4 and Task 6.
5. **A whisper from another player that starts `SDX1:`**: never resolves anything (sender GUID must be the player's), and is not hidden from chat. Test in Task 5.

---

### Task 0: In-game probe (throwaway, user runs it)

Not shipped, not committed to the feature branch. Decides whether 5.2's guard can work.

**Files:**
- Modify: `scripts/probe/SoulDexProbe/Probe.lua` (add `/sdprobe whisper` and `/sdprobe unit`)

- [ ] **Step 1:** `/sdprobe unit` prints, each marked `<secret>` when secret: `UnitIsUnit("mouseover","target")`, `UnitIsUnit("focus","target")`, `UnitExists("mouseover")`, `UnitClassification`, `UnitCreatureType`, `UnitCreatureFamily` for `target`, `UnitIsAFK("player")`, `UnitIsDND("player")`, `C_ChatInfo.InChatMessagingLockdown()`.
- [ ] **Step 2:** `/sdprobe whisper` sends `SDXP:%t` to the player via `C_ChatInfo.SendChatMessage(..., "WHISPER", nil, <own name>)` in a pcall, prints whether the send raised; a `CHAT_MSG_WHISPER` handler prints the text and sender GUID (or `<secret>`) and the line id; on `PLAYER_REGEN_ENABLED` it re-reads the last line id with `C_ChatInfo.GetChatLineText` / `GetChatLineSenderGUID` and prints them. Also print whether `ChatFrameUtil`, `ChatFrameUtil.AddMessageEventFilter`, `ChatEdit_GetLastTellTarget`, `ChatEdit_SetLastTellTarget` exist.
- [ ] **Step 3:** Copy the probe folder into `_forever_/Interface/AddOns/`, full restart. Ask the user to run both commands in SM: out of combat, mid-pull, and during a boss.
- [ ] **Step 4:** Record the answers in the design doc section 8.6. **Stop and talk to the user if `UnitIsUnit` is secret in the dungeon** (the guard in Task 1 can't work). Send blocked mid-combat → continue (those stay Unknown).

---

### Task 1: Whisper format, parsing and the ask decision

**Files:**
- Create: `src/Whisper.lua`
- Create: `spec/Whisper_spec.lua`
- Modify: `SoulDex.toc` (add `src\Whisper.lua` after `src\Catch.lua`)

**Interfaces:**
- Produces:
  - `Whisper.MARKER = "SDX1"`, `Whisper.TIMEOUT = 60`, `Whisper.CEILING = 600`, `Whisper.MAX_NAME = 64`
  - `Whisper.message(token: string) -> string` — `"SDX1:" .. token .. ":%t"`
  - `Whisper.isMarker(text) -> boolean` — plain string starting `"SDX1:"`
  - `Whisper.parse(text) -> token|nil, name|nil` — `token` is non-nil for any well-formed `SDX1:<token>:<rest>`; `name` is nil when `<rest>` fails validation
  - `Whisper.shouldAsk(s: table) -> boolean`; `s` fields: `nameHidden, hasTarget, mouseoverOther, focusOther, chatLocked, afk, dnd` (each `true`/`false`, or `nil` = unreadable)

- [ ] **Step 1: Write failing tests** in `spec/Whisper_spec.lua`:
  - `message("a1")` equals `"SDX1:a1:%t"`.
  - `parse("SDX1:a1:Scarlet Chaplain")` → `"a1", "Scarlet Chaplain"`.
  - `parse("SDX1:a1:%t")` → `"a1", nil` (unexpanded).
  - `parse("SDX1:a1:")`, `parse("SDX1:a1:Bad|cffname")`, `parse("SDX1:a1:a:b")`, `parse("SDX1:a1:line\nbreak")`, and a 65-char name → token `"a1"`, name `nil`.
  - `parse("hello")`, `parse(nil)`, `parse(42)` → `nil, nil`.
  - `isMarker("SDX1:x:y")` true; `isMarker("sdx1:x")`, `isMarker("hi SDX1:")`, `isMarker(nil)` false.
  - `shouldAsk` true only for `{ nameHidden=true, hasTarget=true, mouseoverOther=false, focusOther=false, chatLocked=false, afk=false, dnd=false }`; a table test flips each field in turn to its other value and to `nil` and asserts false.
- [ ] **Step 2:** Run `busted spec/Whisper_spec.lua` → fails (module missing).
- [ ] **Step 3:** Implement the functions above in `src/Whisper.lua` (`local _, ns = ...`, `ns.Whisper = Whisper`); add to `SoulDex.toc`.
- [ ] **Step 4:** Run `busted` and `luacheck .` → all pass.
- [ ] **Step 5:** Commit `feat: whisper marker, reply parsing and the ask decision`.

---

### Task 2: Pending queue with a restriction-aware clock

**Files:**
- Modify: `src/Whisper.lua`, `spec/Whisper_spec.lua`

**Interfaces:**
- Consumes: Task 1 constants.
- Produces:
  - `Whisper.newQueue() -> queue`
  - `queue:add(pend: table, now: number) -> token: string` — stores `pend` (any table; the caller's capture state), gives it `pend.token`; tokens are unique within the queue's life (counter-based, e.g. `string.format("%x", n)`)
  - `queue:get(token) -> pend|nil`
  - `queue:remove(token) -> pend|nil`
  - `queue:tick(now: number, restricted: boolean) -> expired: { pend, ... }` — adds `now - lastTick` to each entry's waited time only when `restricted` is false; removes and returns entries whose waited ≥ `TIMEOUT` or `now - sentAt` ≥ `CEILING`
  - `queue:count() -> number`

- [ ] **Step 1: Write failing tests:**
  - add at t=0, `tick(59,false)` → none expired; `tick(61,false)` → that pend expired, `get` nil.
  - add at t=0, `tick(100,true)`, `tick(150,false)` → none (only 50 s unrestricted); `tick(161,false)` → expired.
  - add at t=0, ticks every 10 s restricted until 600 → expired at 600, not 590.
  - two adds give two different tokens; `remove` of one leaves the other.
- [ ] **Step 2:** Run → fails.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `busted`, `luacheck .` → pass.
- [ ] **Step 5:** Commit `feat: pending whisper queue that waits out combat`.

---

### Task 3: Dex fills missing details on a later catch

**Files:**
- Modify: `src/Dex.lua` (`methods:recordMob`, existing-entry branch), `spec/Dex_spec.lua`

**Interfaces:**
- Produces: no new function. `recordMob(info, ctx)` on an existing entry sets `classification`, `creatureType`, `family` when the entry's is nil and `info`'s is a string; if classification was filled, `entry.points = math.max(entry.points or 0, ns.Points.forMob(info.classification))`. Never overwrites a present value; never lowers points.

- [ ] **Step 1: Write failing tests:** record "Scarlet Chaplain" with `classification=nil` (points 1, as a normal mob); record again with `classification="elite"` → entry classification `"elite"`, `entry.points` equals `Points.forMob("elite")`, `dex:score()` grew by the difference plus the repeat claim's worth. A third record with `classification="normal"` leaves `"elite"`.
- [ ] **Step 2:** Run → fails.
- [ ] **Step 3:** Implement in the existing-entry path of `recordMob`.
- [ ] **Step 4:** `busted`, `luacheck .` → pass.
- [ ] **Step 5:** Commit `feat: fill a soul's missing details on a later catch`.

---

### Task 4: Pending shard entries

**Files:**
- Modify: `src/Shards.lua`, `spec/Shards_spec.lua`

**Interfaces:**
- Produces:
  - Map entry may be `{ soul = false, pending = { token = string, ctx = table }, seen = n }`.
  - `Shards.update` keeps `pending` on entries it carries over (today it rebuilds `{ soul, seen }`).
  - `Shards.assignPending(map, guid, token, ctx, now) -> newMap`
  - `Shards.pendingOf(map, guid) -> pending|nil`
  - `Shards.findPending(map, token) -> guid|nil`
  - `Shards.allPending(map) -> { { guid = g, pending = p }, ... }` (sorted by guid)
  - `Shards.assign` (existing) clears `pending` (it writes a fresh entry).

- [ ] **Step 1: Write failing tests:** `assignPending` then `update` with the guid present → `pendingOf` still returns the token and ctx; `findPending(token)` returns the guid; `assign(guid, soul)` → `pendingOf` nil and `soulOf` the soul; `allPending` lists exactly the pending guids; `soulOf` of a pending entry is nil.
- [ ] **Step 2:** Run → fails.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `busted`, `luacheck .` → pass.
- [ ] **Step 5:** Commit `feat: shards can wait for a soul's name`.

---

### Task 5: Sending, receiving and hiding the whispers

**Files:**
- Modify: `src/Capture.lua` (`Capture.start`: `targetInfo`, handlers; new `Capture.askState(unit)`), `.luacheckrc`, `spec/Capture_spec.lua`

**Interfaces:**
- Consumes: Task 1 `shouldAsk`, `message`, `parse`, `isMarker`; Task 2 queue.
- Produces:
  - `Capture.askState() -> table` for `Whisper.shouldAsk`, built from: name secret (`not readable(UnitName("target"))`), `UnitExists("target")`, `mouseoverOther = UnitExists("mouseover") and not UnitIsUnit("mouseover","target")` (`false` when no mouseover, `nil` when either call is unreadable), same for `focus`, `chatLocked()` (existing), `UnitIsAFK("player")`, `UnitIsDND("player")`.
  - `Capture.readDetails(unit) -> { level, classification, creatureType, family, isPlayer }` (each readable or nil; skull level → nil as in `readUnit`).
  - When `targetInfo` returns `info.unknown` **and** `shouldAsk(askState())`: build `pend = { details = readDetails("target"), state = "waiting" }`, `token = queue:add(pend, GetTime())`, send `C_ChatInfo.SendChatMessage(Whisper.message(token), "WHISPER", nil, ownName)` in `call`; a raising send → `queue:remove(token)`, plain unknown. On success the capture's info becomes `{ unknown = true, pend = pend, isPlayer = details.isPlayer }`. Own name: `UnitName("player")` (+ `"-" .. realm` only if the client's whisper needs it; Task 0 tells).
  - Before sending, remember `ChatEdit_GetLastTellTarget()` if it exists and restore it after (`ChatEdit_SetLastTellTarget`), each in `call`.
  - `onName(token, name)` (local, used by Task 6): sets `pend.name = name`, `pend.state = "named"`.
  - `CHAT_MSG_WHISPER(text, …, lineID [11], senderGUID [12])`: if text and sender are plain, `parse(text)`; act only when the token is in the queue and `senderGUID == UnitGUID("player")` (both plain); valid name → `onName`; invalid → `pend.state = "failed"`, remove. If text or sender is secret and `lineID` is a plain number and the queue isn't empty, keep `lineID` (max 32) for re-reading.
  - Re-read kept line ids via `C_ChatInfo.GetChatLineText` / `GetChatLineSenderGUID` on `PLAYER_REGEN_ENABLED`, `ADDON_RESTRICTION_STATE_CHANGED`, `ENCOUNTER_END`, `ZONE_CHANGED_NEW_AREA` (add the last to `OPTIONAL_EVENTS`), each through the same accept path; drop a line id once read or after `CEILING`.
  - Chat filter on `CHAT_MSG_WHISPER` and `CHAT_MSG_WHISPER_INFORM` (registered once at start; `ChatFrameUtil.AddMessageEventFilter` if present, else `ChatFrame_AddMessageEventFilter`): returns true when `isMarker(msg)` and the line is the player's own (sender GUID arg 12 equals the player's, or the sender name equals the player's name; unreadable → not hidden).
  - New `read_globals`: `ChatFrameUtil`, `ChatEdit_GetLastTellTarget`, `ChatEdit_SetLastTellTarget`, `UnitExists`, `UnitIsUnit`, `UnitIsAFK`, `UnitIsDND` (whichever are new).

- [ ] **Step 1: Write failing tests** in `spec/Capture_spec.lua` ("soul-name whispers"), using the existing world stubs plus stubs for the new APIs and a recording `C_ChatInfo.SendChatMessage`:
  - Hidden-name Drain Soul channel start, no mouseover/focus, not AFK, chat open → exactly one send, text matches `^SDX1:[^:]+:%%t$`, channel `"WHISPER"`, target is the player's name.
  - Same with `mouseover` a different unit → no send. With `UnitIsUnit` returning the secret stub → no send. With AFK → no send. With chat locked → no send. With a readable name → no send.
  - `SendChatMessage` raising → no error escapes, no pending entry left.
  - Last tell target is restored after the send.
  - Whisper event with the right token from the player's GUID → `pend.state == "named"`; same text from another GUID → nothing changes.
  - Secret text with a line id → nothing yet; after `PLAYER_REGEN_ENABLED` with `GetChatLineText` returning the line → named.
  - Filter: hides `SDX1:` lines from the player; does not hide them from another sender; does not hide other text.
- [ ] **Step 2:** Run → fails.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `busted`, `luacheck .` → pass.
- [ ] **Step 5:** Commit `feat: ask for a hidden soul's name by whispering yourself`.

---

### Task 6: Holding the shard, resolving and timing out

**Files:**
- Modify: `src/Capture.lua` (`Capture.record`, `scanBags`, new resolve path, a ticker, `ns.OnLoaded`), `spec/Capture_spec.lua`

**Interfaces:**
- Consumes: Task 4 shard functions, Task 5 `pend` / `onName`, Task 3 Dex behaviour.
- Produces:
  - `Capture.record(dex, capture)` for `info.unknown` with `info.pend`:
    - `pend.state == "named"` → record as a named catch with `info = details + { name = pend.name }` (`guid` nil; `recordCatch` treats it as mob/player; in a raid instance it falls through to "mob", as the design says).
    - `pend.state == "waiting"` → returns `nil, nil, { park = true, token = pend.token, ctx = ctx }`; `scanBags` stores it with `Shards.assignPending` (no dex record, no `afterCatch`) and sets `pend.shard = guid`.
    - `"failed"` or no `pend` → Unknown, as today.
  - `onName` (Task 5) and failure/expiry: if `pend.shard` is set and `Shards.pendingOf` still has it, record now (named → `Capture.recordCatch` with the saved `ctx` and the named info; failed/expired → `dex:recordUnknown(ctx)`), `Shards.assign` the soul (or the Unknown soul table), then `afterCatch` for a named one. If `pend.shard` is nil, only set the state; the shard records when it arrives.
  - A 1 s `C_Timer.NewTicker` (or self-rescheduling `C_Timer.After`) while the queue is non-empty: `queue:tick(GetTime(), restricted)` where `restricted = chatLocked() or InCombatLockdown()`; each expired pend → `state = "failed"` and the resolve path above. Add `InCombatLockdown`, `C_Timer.NewTicker` to stubs/read_globals as used.
  - `ns.OnLoaded`: for each `Shards.allPending(db.shardSouls)` → `dex:recordUnknown(p.pending.ctx)` and `Shards.assign` the Unknown soul (once; the entry is then no longer pending).

- [ ] **Step 1: Write failing tests** ("holding the shard"):
  - Hidden-name drain → shard appears → no dex record, no popup timer, shard pending → whisper reply → mob recorded with that name and the saved zone, shard soul named, popup scheduled.
  - Reply first, then shard → recorded named at the shard scan.
  - Reply never comes: advance 61 s unrestricted (tick) → one Unknown soul in that zone, shard holds the Unknown soul.
  - 90 s in combat (`InCombatLockdown` true) then reply via line-id re-read at `PLAYER_REGEN_ENABLED` → named.
  - Two hidden drains (tokens A, B), shards gA, gB; reply B then A → each shard gets its own name.
  - Saved map with a pending entry, then `ns.OnLoaded` → `db.unknown[zone].count == 1`, entry no longer pending; calling `OnLoaded` logic again doesn't add a second.
  - Readable-name catch path unchanged (existing tests still pass).
- [ ] **Step 2:** Run → fails.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `busted`, `luacheck .` → pass.
- [ ] **Step 5:** Commit `feat: hold a shard until its soul's name arrives`.

---

### Task 7: Docs, rules and changelog

**Files:**
- Modify: `docs/superpowers/specs/2026-11-10-souldex-design.md` (sections 3, 4 Unknown soul, 6 game layer, 9 in-game checks: copy section 8 of the design doc), `CLAUDE.md` (Code rules: "except guild announcements" → "except guild announcements and the hidden `SDX1:` whispers SoulDex sends to the player themself"; add `src/Whisper.lua` to the Layout table), `CHANGELOG.md` (`## [Unreleased]`: one line, e.g. "Souls caught in dungeons now get their names (SoulDex quietly whispers you to read them).").
- Also: known limitations in the spec — casts through other macro targets can be misnamed; chat addons that read whispers themselves (WIM, Prat, ElvUI) may show `SDX1:` lines; whispers can't be sent during chat lockdown, so those stay Unknown.

- [ ] **Step 1:** Make the edits.
- [ ] **Step 2:** `busted`, `luacheck .` → pass.
- [ ] **Step 3:** Commit `docs: soul names through a self-whisper in the spec, rules and changelog`.

---

### Task 8: Build and hand to the user

- [ ] **Step 1:** `bash scripts/build.sh` → "Built SoulDex …", and `_forever_/Interface/AddOns/SoulDex/src/Whisper.lua` exists.
- [ ] **Step 2:** Tell the user: **full restart** (new file in the .toc), then the in-game checks from design section 8 (1–5), with what each should show.
