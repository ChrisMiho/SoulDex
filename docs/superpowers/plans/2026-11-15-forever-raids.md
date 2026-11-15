# Forever Raids (TBD rosters) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** List WoW: Forever's two new raids (The Barrow Deeps, Hyjal Summit) in the Raids tab now, marked TBD, collecting every soul claimed inside them until their real creature lists can ship.

**Architecture:** A small hand-kept data file adds the two raids to `ns.RaidData` with `tbd = true`, no creature list and no instance ID. Because the instance IDs are not published, the addon learns each one the first time the player claims a soul inside a raid-type instance whose name matches, and saves it per character. TBD raids are listed but left out of every "N / M" total and milestone. The existing rule "an unlisted NPC caught in a listed raid is still kept under that raid" does the collecting.

**Tech Stack:** Lua 5.1, busted, luacheck. No new libraries.

**Spec:** `docs/superpowers/specs/2026-11-10-souldex-design.md` (sections 2, 4.3, 5.4, 6 milestones, 9). Task 5 updates it; the user's decisions behind this plan are in "Decisions" below.

## Decisions (from the user, 2026-11-15)

- Scope is **raids now, dungeons later**: only the two new raids are added. The nine new 5-player dungeons get their own plan; the data file made here is where they will go.
- TBD raids are **listed, not counted**: they appear in the Raids list but are left out of the Raids header total, the Me tile's "N / M", their own "<Raid> Drained" milestone and Raid Reaper, until real data ships.

Calls made while planning (the user should check them):

- **[call]** The two Forever raids are listed first, above the vanilla raids (they are the ones that exist in the game today).
- **[call]** Instance IDs are learned by instance name (English client only), ignoring case and a leading "The ".
- **[call]** A TBD raid's row reads `TBD` until something is claimed there, then `N / ?`.

## What is known (source: Blizzard, "World of Warcraft: Forever Raid Overview", news 24303009)

| Raid | Players | Bosses | Boss names | Instance ID |
|------|---------|--------|------------|-------------|
| The Barrow Deeps | 10 | 8 | not published | not published |
| Hyjal Summit | 20 | 13 | not published | not published |

Both open on 2026-12-09. Do not reuse instance ID 534 (the Burning Crusade Hyjal Summit): it is a different instance.

## Global Constraints

- Every file starts with `local addonName, ns = ...` (or `local _, ns = ...`); share through `ns`, no new globals.
- Pure modules (`Raids`, `Dex`, `Milestones`, `View`, `UIFormat`) call no WoW API and are tested with busted through `LoadAddonFile`.
- `src/RaidData.lua` is generated: never hand-edit it. The Forever raids go in a separate hand-kept file.
- Every value from the WoW API is checked for secret values before use (in `Capture`, the local `str`/`num` helpers).
- Never record a wrong name in the dex.
- Tabs for Lua indentation; max line length 120.
- A new `src/` file goes in `SoulDex.toc` above `src\Init.lua`, and must be `git add`ed to be built.
- Player-facing text: soul-hunter voice; souls are "claimed"; no Pokémon names.
- `luacheck .` and `busted` must both pass before each commit.
- Add a line under `## [Unreleased]` in `CHANGELOG.md` for each user-facing change.

## Review Focus

1. The instance name is secret, nil or empty: nothing is learned and the catch is recorded as a plain mob under "Raids", as today (Task 2).
2. A non-English client, or a name that does not match: same fallback, no error (Task 2; listed as a known limitation in Task 5).
3. A saved learned ID that is damaged (not a number), names an unknown raid key, or collides with another raid's ID: ignored on load, no error, the other raid is untouched (Tasks 1 and 2).
4. Selecting a TBD raid that has no instance ID yet: the row is selectable and the right pane shows the TBD note, not "No raid data." (Tasks 3 and 4).
5. A player who already earned Raid Reaper or sees "Raids 7 / 7": adding TBD raids must not change the goal of 7 or un-finish anything (Task 3).

## File Structure

- Create `src/ForeverData.lua`: hand-kept list of Forever's own raids, inserted at the front of `ns.RaidData`. Later plans add dungeons here.
- Modify `src/Raids.lua`: lookups by key and name, learning an instance ID, the list of completable raids.
- Modify `src/Dex.lua`: saves learned IDs (`db.instances`), `raidFor`.
- Modify `src/Capture.lua`: passes the instance name; uses `dex:raidFor`.
- Modify `src/Milestones.lua`, `src/View.lua`: leave TBD raids out of totals; raid rows carry `key`, `tbd`.
- Modify `src/UIFormat.lua`, `src/UI.lua`: TBD row text, TBD note, selection by raid key.
- Modify `SoulDex.toc`, the spec, `CHANGELOG.md`, `README.md`.

---

### Task 1: Forever raid data and raid lookups

**Files:**
- Create: `src/ForeverData.lua`, `spec/ForeverData_spec.lua`
- Modify: `src/Raids.lua`, `SoulDex.toc` (add `src\ForeverData.lua` on the line after `src\RaidData.lua`)
- Test: `spec/Raids_spec.lua`, `spec/ForeverData_spec.lua`

**Interfaces:**
- Produces, raid table shape (new optional fields): `{ key, name, instanceID? (number), mobs = {...}, tbd? = true, bossCount? (number) }`
- Produces: `Raids.byInstance(instanceID)` returns nil for a nil `instanceID` (today it would match a raid with no ID)
- Produces: `Raids.byKey(key) -> raid | nil`
- Produces: `Raids.byName(name) -> raid | nil`: only raids with no `instanceID`; compares lower-cased names with a leading "the " and outer spaces removed; nil for a non-string or empty name
- Produces: `Raids.learn(key, instanceID) -> boolean`: sets `raid.instanceID`; returns true when the raid now has that ID. Returns false and changes nothing when the key is unknown, `instanceID` is not a number, the raid already has a different ID, or another raid has that ID
- Produces: `Raids.completable() -> { raid, ... }`: the raids without `tbd`, in list order

- [ ] **Step 1: Write the failing tests**

`spec/ForeverData_spec.lua`:

```lua
describe("ForeverData", function()
	it("puts the Forever raids first, TBD, with no instance id", function()
		local ns = LoadAddonFile("src/RaidData.lua")
		LoadAddonFile("src/ForeverData.lua", ns)
		local bd, hyjal = ns.RaidData[1], ns.RaidData[2]
		assert.same({ key = "BD", name = "The Barrow Deeps", bossCount = 8, tbd = true, mobs = {} }, bd)
		assert.same({ key = "Hyjal", name = "Hyjal Summit", bossCount = 13, tbd = true, mobs = {} }, hyjal)
		assert.equal("ZG", ns.RaidData[3].key)
		assert.equal(9, #ns.RaidData)
	end)

	it("loads without the generated data and has unique keys", function()
		local ns = LoadAddonFile("src/ForeverData.lua")
		assert.equal(2, #ns.RaidData)
		local all, seen = LoadAddonFile("src/ForeverData.lua", LoadAddonFile("src/RaidData.lua")).RaidData, {}
		for _, raid in ipairs(all) do
			assert.is_nil(seen[raid.key])
			seen[raid.key] = true
		end
	end)
end)
```

Add to `spec/Raids_spec.lua` a new `describe("Raids with TBD raids", ...)` whose `before_each` builds `ns = { RaidData = { {key="BD", name="The Barrow Deeps", tbd=true, mobs={}}, {key="MC", name="Molten Core", instanceID=409, mobs={{id=1,name="A"}}} } }` and loads `src/Raids.lua`:

```lua
it("never matches a raid without an id by a nil id", function()
	assert.is_nil(Raids.byInstance(nil))
	assert.is_nil(Raids.find(nil, 1))
end)
it("finds a raid by key", function()
	assert.equal("Molten Core", Raids.byKey("MC").name)
	assert.is_nil(Raids.byKey("nope"))
end)
it("finds an id-less raid by name, loosely", function()
	assert.equal("BD", Raids.byName("The Barrow Deeps").key)
	assert.equal("BD", Raids.byName("  barrow deeps ").key)
	assert.is_nil(Raids.byName("Molten Core")) -- has an id already
	assert.is_nil(Raids.byName("Barrow"))
	assert.is_nil(Raids.byName(""))
	assert.is_nil(Raids.byName(nil))
	assert.is_nil(Raids.byName(42))
end)
it("learns an instance id once", function()
	assert.is_true(Raids.learn("BD", 3001))
	assert.equal("BD", Raids.byInstance(3001).key)
	assert.is_nil(Raids.byName("The Barrow Deeps"))
	assert.is_true(Raids.learn("BD", 3001))
	assert.is_false(Raids.learn("BD", 3002))
	assert.equal(3001, Raids.byKey("BD").instanceID)
end)
it("refuses a bad or colliding id", function()
	assert.is_false(Raids.learn("BD", 409))
	assert.is_false(Raids.learn("BD", "3001"))
	assert.is_false(Raids.learn("BD", nil))
	assert.is_false(Raids.learn("nope", 3001))
	assert.is_nil(Raids.byKey("BD").instanceID)
	assert.equal("MC", Raids.byInstance(409).key)
end)
it("lists only completable raids", function()
	local list = Raids.completable()
	assert.equal(1, #list)
	assert.equal("MC", list[1].key)
end)
```

- [ ] **Step 2: Run them to see them fail**

Run: `busted spec/Raids_spec.lua spec/ForeverData_spec.lua`
Expected: FAIL (`src/ForeverData.lua` not found; `byKey` is nil).

- [ ] **Step 3: Create `src/ForeverData.lua`**

Header comment: hand-kept; WoW: Forever's own raids; source "Blizzard, World of Warcraft: Forever Raid Overview (news 24303009), read 2026-11-15"; `tbd = true` means the creature list is not known yet; an entry gets its `instanceID`, `mobs` and loses `tbd` when the data is known. Then `ns.RaidData = ns.RaidData or {}` and insert the two raids (exact tables from the test) at positions 1 and 2.

- [ ] **Step 4: Implement the five functions in `src/Raids.lua`** to the signatures in Interfaces.

- [ ] **Step 5: Add the toc line, run everything**

Run: `luacheck . && busted`
Expected: both pass (existing specs build their own `RaidData`, so none change).

- [ ] **Step 6: Commit**

```bash
git add src/ForeverData.lua spec/ForeverData_spec.lua src/Raids.lua spec/Raids_spec.lua SoulDex.toc
git commit -m "feat: list the Forever raids as TBD data"
```

---

### Task 2: Learn a TBD raid's instance ID from the first claim

**Files:**
- Modify: `src/Dex.lua` (`Dex.new`, new method), `src/Capture.lua` (`buildContext` ~line 280, `recordCatch` ~line 171)
- Test: `spec/Dex_spec.lua`, `spec/Capture_spec.lua`

**Interfaces:**
- Consumes: `Raids.byInstance`, `Raids.byName`, `Raids.learn` (Task 1)
- Produces: `db.instances` — saved table `{ [raidKey] = instanceID }`; `Dex.new(db)` creates it when missing or damaged, then calls `ns.Raids.learn(key, id)` for each pair (bad pairs are simply refused by `learn`)
- Produces: `dex:raidFor(instanceID, instanceName) -> raid | nil`: the raid with that ID; else, when `instanceID` is a number, the raid `Raids.byName(instanceName)` finds, after `Raids.learn` accepts the ID, which is then saved in `db.instances`; else nil
- Produces: `ctx.instanceName` (string or nil) from `Capture.buildContext()`: the first return of `GetInstanceInfo`, passed through the same secret-value `str` helper as `instanceType`

- [ ] **Step 1: Write the failing tests**

In `spec/Dex_spec.lua`, add `{ key = "BD", name = "The Barrow Deeps", tbd = true, mobs = {} }` as a second entry of the fixture `RaidData`, then:

```lua
describe("raidFor", function()
	it("returns a listed raid by id", function()
		assert.equal("MC", dex:raidFor(409, "anything").key)
	end)
	it("learns a TBD raid by name and saves the id", function()
		assert.equal("BD", dex:raidFor(3001, "The Barrow Deeps").key)
		assert.same({ BD = 3001 }, db.instances)
		assert.equal("BD", dex:raidFor(3001, nil).key)
	end)
	it("learns nothing without a usable name or id", function()
		assert.is_nil(dex:raidFor(3001, nil))
		assert.is_nil(dex:raidFor(3001, "Odd Keep"))
		assert.is_nil(dex:raidFor(nil, "The Barrow Deeps"))
		assert.same({}, db.instances)
	end)
	it("keeps what an unlisted creature gives under the learned raid", function()
		dex:raidFor(3001, "The Barrow Deeps")
		local r = dex:recordRaid({ name = "Barrow Thing", classification = "elite" }, { time = 100 }, 3001, 555)
		assert.is_true(r.isNew)
		assert.is_false(db.raids[555].known)
		assert.equal(3001, db.raids[555].instanceID)
	end)
end)

describe("saved instance ids", function()
	it("are applied on load", function()
		ns.Dex.new({ instances = { BD = 3001 } })
		assert.equal("BD", ns.Raids.byInstance(3001).key)
	end)
	it("are ignored when damaged or colliding", function()
		assert.has_no.errors(function()
			ns.Dex.new({ instances = { BD = 409, nope = 5, [7] = "x" } })
			ns.Dex.new({ instances = "broken" })
		end)
		assert.is_nil(ns.Raids.byKey("BD").instanceID)
		assert.equal("MC", ns.Raids.byInstance(409).key)
	end)
end)
```

In `spec/Capture_spec.lua`, inside `describe("recordCatch", ...)` (the `load()` there loads the real `RaidData`; add `"ForeverData"` after `"RaidData"` in that spec's file list at ~line 179):

```lua
it("files a claim in a TBD raid under that raid, learning its id from the name", function()
	local ns, dex = setup()
	local cand = { guid = "Creature-0-1-3001-2-555-3", info = { name = "Barrow Thing", classification = "elite" } }
	local raidCtx = { time = 100, myLevel = 60, zone = "The Barrow Deeps", group = "Raids",
		instanceName = "The Barrow Deeps" }
	local r, kind = ns.Capture.recordCatch(dex, cand, raidCtx, "raid", 3001)
	assert.equal("raid", kind)
	assert.is_true(r.isNew)
	assert.equal("Barrow Thing", dex.db.raids[555].name)
	assert.is_nil(dex.db.mobs["Barrow Thing"])
	assert.equal(3001, dex.db.instances.BD)
end)
it("does not learn from a party-type instance or without a name", function()
	local ns, dex = setup()
	local cand = { guid = "Creature-0-1-3001-2-555-3", info = { name = "Barrow Thing", classification = "elite" } }
	local named = { time = 100, zone = "X", group = "Dungeons", instanceName = "The Barrow Deeps" }
	local _, kind = ns.Capture.recordCatch(dex, cand, named, "party", 3001)
	assert.equal("mob", kind)
	local unnamed = { time = 100, zone = "X", group = "Raids" }
	_, kind = ns.Capture.recordCatch(dex, cand, unnamed, "raid", 3001)
	assert.equal("mob", kind)
	assert.same({}, dex.db.instances)
end)
```

Next to the existing "buildContext falls back when zone and map values are secret" test (~line 1069), using that test's way of stubbing `GetInstanceInfo` and secret values: one test that `buildContext().instanceName` is `"Hyjal Summit"` when `GetInstanceInfo` returns it first, and one that it is nil when that first value is secret.

- [ ] **Step 2: Run them to see them fail**

Run: `busted spec/Dex_spec.lua spec/Capture_spec.lua`
Expected: FAIL (`raidFor` is nil; `instanceName` is nil).

- [ ] **Step 3: Implement in `src/Dex.lua`**: add `"instances"` to the key list in `Dex.new`, apply saved pairs with `ns.Raids.learn`, add `methods:raidFor`.

- [ ] **Step 4: Implement in `src/Capture.lua`**: `buildContext` sets `ctx.instanceName`; in `recordCatch` the condition `ns.Raids.byInstance(instanceID)` becomes `dex:raidFor(instanceID, ctx.instanceName)`.

- [ ] **Step 5: Run everything**

Run: `luacheck . && busted`
Expected: both pass.

- [ ] **Step 6: Commit**

```bash
git add src/Dex.lua src/Capture.lua spec/Dex_spec.lua spec/Capture_spec.lua
git commit -m "feat: learn a TBD raid's instance id from the first claim"
```

---

### Task 3: TBD raids are listed, not counted

**Files:**
- Modify: `src/Milestones.lua` (Raids group, ~lines 55-61), `src/View.lua` (`View.raids` ~line 149, `View.meCard` tile ~line 494)
- Test: `spec/Milestones_spec.lua`, `spec/View_spec.lua`

**Interfaces:**
- Consumes: `Raids.completable()` (Task 1)
- Produces: `View.raids(dex)` rows: `{ key, instanceID, name, caught, total, done, tbd }`. For a TBD raid: `tbd = true`, `done = false`, `total = 0`, and `caught` = the number of `db.raids` entries whose `instanceID` equals the raid's (0 while the raid has no ID). For other raids `tbd = false` and the rest is as today
- Produces: Milestones: no `raid_<key>` milestone for a TBD raid; `raids_all` goal is `#Raids.completable()`
- Produces: Me tile "Raids": `<completed> / <#Raids.completable()>`

- [ ] **Step 1: Write the failing tests**

In both specs, add `{ key = "BD", name = "The Barrow Deeps", tbd = true, mobs = {} }` as the **first** entry of the fixture `RaidData`, and fix the indexes the existing tests use (`rows[1]` becomes `rows[2]`, `ns.RaidData[2] = nil` becomes `[3]`, and so on). In `spec/View_spec.lua` the existing `assert.same` on the Molten Core row gains `key = "MC", tbd = false`.

`spec/Milestones_spec.lua`:

```lua
it("leaves TBD raids out of the raid milestones", function()
	local ids = {}
	for _, item in ipairs(ns.Milestones.list(dex)) do
		ids[item.id] = item
	end
	assert.is_nil(ids.raid_BD)
	assert.equal(2, ids.raids_all.goal) -- Molten Core and Empty Raid; not the TBD one
end)
```

The existing "earns raids_all when every raid in the list is complete" test (with `ns.RaidData[3] = nil` after the index fix) now has the TBD raid still in the list and must keep passing unchanged otherwise: that is the Raid Reaper check.

`spec/View_spec.lua`:

```lua
it("lists a TBD raid first, uncounted", function()
	local rows = View.raids(dex)
	assert.same({ key = "BD", name = "The Barrow Deeps", caught = 0, total = 0, done = false, tbd = true }, rows[1])
end)
it("counts what was claimed in a TBD raid once its id is known", function()
	dex:raidFor(3001, "The Barrow Deeps")
	dex:recordRaid(mob("Barrow Thing"), ctx("The Barrow Deeps", "Raids"), 3001, 555)
	local row = View.raids(dex)[1]
	assert.equal(3001, row.instanceID)
	assert.equal(1, row.caught)
	assert.is_false(row.done)
	local mobs = View.raidMobs(dex, 3001, nil)
	assert.equal(1, #mobs)
	assert.equal("Barrow Thing", mobs[1].name)
end)
it("keeps TBD raids out of the header and Me totals", function()
	dex:raidFor(3001, "The Barrow Deeps")
	dex:recordRaid(mob("Barrow Thing"), ctx("The Barrow Deeps", "Raids"), 3001, 555)
	local _, right = View.header(dex, "Raids")
	assert.truthy(right:find("^0/"))
	local card = View.meCard(dex, nil, nil, 0)
	assert.equal("Raids", card.tiles[3].label)
	assert.equal("0 / 2", card.tiles[3].value)
end)
it("returns no rows for a raid with no id yet", function()
	assert.same({}, View.raidMobs(dex, nil, nil))
end)
```

- [ ] **Step 2: Run them to see them fail**

Run: `busted spec/Milestones_spec.lua spec/View_spec.lua`
Expected: FAIL (`raid_BD` exists; goal is 3; rows lack `key`).

- [ ] **Step 3: Implement** in `src/Milestones.lua` and `src/View.lua` to the Interfaces block. `View.header` needs no change (a TBD raid's total is 0); the test pins it.

- [ ] **Step 4: Run everything**

Run: `luacheck . && busted`
Expected: both pass.

- [ ] **Step 5: Commit**

```bash
git add src/Milestones.lua src/View.lua spec/Milestones_spec.lua spec/View_spec.lua
git commit -m "feat: keep TBD raids out of totals and milestones"
```

---

### Task 4: Show TBD raids in the Raids tab

**Files:**
- Modify: `src/UIFormat.lua` (`F.raidRows` ~line 221, new `F.tbdNote`), `src/UI.lua` (Raids branch ~lines 149-153)
- Test: `spec/UIFormat_spec.lua`, `spec/UI_spec.lua`

**Interfaces:**
- Consumes: `View.raids` rows with `key`, `tbd` (Task 3); `Raids.byKey` (Task 1)
- Produces: `F.raidRows(rows, selectedKey)`: `value = row.key`, `selected = row.key == selectedKey`. A TBD row: `right = "TBD"` when `caught == 0`, else `caught .. " / ?"`; `rightColor = C.MUTED`; no `bar`
- Produces: `F.tbdNote(raid) -> row`: `F.note` with exactly `"Roster still sealed: 8 bosses wait inside. Every soul you claim here is kept."` (the number is `raid.bossCount`), or `"Roster still sealed. Every soul you claim here is kept."` when `bossCount` is nil
- Produces: in `UI.lua`, `state.sel.Raids` holds a raid **key** (was an instance ID). Right pane for the selected raid: `F.raidMobRows(View.raidMobs(dex, raid.instanceID, other()))`, with `F.tbdNote(raid)` put first when `raid.tbd`. "No raid data." stays for the case of no raids at all

- [ ] **Step 1: Write the failing tests**

`spec/UIFormat_spec.lua`: in the existing "shows raid progress or a check when done" test add `key = "ZG"` / `key = "MC"` to the rows, pass `"MC"` as the selection, and assert `rows[2].value == "MC"`. New tests:

```lua
it("marks a TBD raid and counts what was claimed there", function()
	local rows = F.raidRows({
		{ key = "BD", name = "The Barrow Deeps", caught = 0, total = 0, done = false, tbd = true },
		{ key = "Hyjal", instanceID = 3002, name = "Hyjal Summit", caught = 4, total = 0, done = false, tbd = true },
	}, "BD")
	assert.equal("TBD", rows[1].right)
	assert.equal("4 / ?", rows[2].right)
	assert.is_nil(rows[1].bar)
	assert.is_nil(rows[2].bar)
	assert.equal("BD", rows[1].value)
	assert.is_true(rows[1].selected)
	assert.is_false(rows[2].selected)
end)
it("writes the TBD note", function()
	assert.equal("Roster still sealed: 8 bosses wait inside. Every soul you claim here is kept.",
		F.tbdNote({ bossCount = 8 }).text)
	assert.equal("Roster still sealed. Every soul you claim here is kept.", F.tbdNote({}).text)
end)
```

`spec/UI_spec.lua`: add a TBD raid with no `instanceID` as the first entry of its fixture `RaidData`; using the spec's existing way of opening the Raids tab and reading what the two lists were given, assert that (a) the TBD raid is the selected left row, (b) the right list's first row text is the TBD note and it has no "No raid data." row, (c) selecting the second raid shows its `? ? ?` rows as before.

- [ ] **Step 2: Run them to see them fail**

Run: `busted spec/UIFormat_spec.lua spec/UI_spec.lua`
Expected: FAIL (`tbdNote` is nil; `value` is an instance ID).

- [ ] **Step 3: Implement** `F.raidRows`, `F.tbdNote` and the `UI.lua` Raids branch (`F.pick(raids, "key", state.sel.Raids)`).

- [ ] **Step 4: Run everything**

Run: `luacheck . && busted`
Expected: both pass.

- [ ] **Step 5: Commit**

```bash
git add src/UIFormat.lua src/UI.lua spec/UIFormat_spec.lua spec/UI_spec.lua
git commit -m "feat: show TBD raids in the Raids tab"
```

---

### Task 5: Spec, changelog, README, build

**Files:**
- Modify: `docs/superpowers/specs/2026-11-10-souldex-design.md`, `CHANGELOG.md`, `README.md`

- [ ] **Step 1: Update the spec** so it agrees with the code. Mark each change "(changed after 1.2.4: Forever raids.)" and tag the decisions **[user]** / **[call]** as in "Decisions" above.
  - Section 2, non-goal "No content past vanilla for now": now vanilla raids plus Forever's two new raids as TBD; the nine new dungeons are still out (own plan later).
  - Section 4.3: a raid with no instance ID in the data is matched by its instance name the first time a soul is claimed there; the ID is saved in `SoulDexDB.instances`.
  - Section 5.4: `src/ForeverData.lua` is hand-kept beside the generated file; the table of what is known and its source; a TBD raid shows `TBD` or `N / ?`, the note text, and collects claimed souls as unlisted entries that fill their slots when the list ships; listed, not counted.
  - Milestones (the "<Raid> Drained" / "Raid Reaper" paragraph) and the Me tile ("1 / 7"): TBD raids are left out.
  - Section 9, a new **Forever raids** block, exactly these checks:
    - Raids tab: The Barrow Deeps and Hyjal Summit are the top two rows, each reading `TBD`; clicking one shows "Roster still sealed: 8 bosses wait inside..." (13 for Hyjal Summit). The Me tile still reads "N / 7" and Milestones has no "The Barrow Deeps Drained".
    - From 2026-12-09, inside each raid: `/dump GetInstanceInfo()`. The first value must be the raid's name as listed, the second `"raid"`; write down the eighth (the instance ID).
    - Claim a soul there: the popup shows, the soul is listed under that raid in the Raids tab (not under Mobs), and the row reads `1 / ?`. After `/reload` it is still there.
    - For each boss and a few trash mobs, `/dump UnitGUID("target")`: write down the name and the sixth dash-separated field. Also write down the names of the raid's boss achievements. These fill `src/ForeverData.lua`.
  - Known limitations: learning by name needs the English client (elsewhere those claims go under Mobs > Raids until the ID ships); a boss claimed in a TBD raid scores by its classification, not the raid-boss 25, until it is listed; a friend's souls from a TBD raid show only once your own client has learned that raid's ID.
- [ ] **Step 2: `CHANGELOG.md`**, under `## [Unreleased]`: "New: WoW: Forever's own raids, The Barrow Deeps and Hyjal Summit, are in the Raids list. Their rosters are still TBD: every soul you claim inside is kept and will fill its slot when the list ships. They don't count toward Raid Reaper yet."
- [ ] **Step 3: `README.md`**: in "The raids" feature text (~line 33) mention the two Forever raids as TBD; in the Data section (~line 132) say the Forever raid names and boss counts come from Blizzard's raid overview and are hand-kept in `src/ForeverData.lua`.
- [ ] **Step 4: Verify**

Run: `luacheck . && busted && scripts/build.sh --no-install`
Expected: lint and tests pass; the zip is made and contains `src/ForeverData.lua` (`unzip -l .release/*.zip | grep ForeverData`).

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/specs/2026-11-10-souldex-design.md CHANGELOG.md README.md
git commit -m "docs: Forever raids as TBD in the spec, changelog and README"
```
