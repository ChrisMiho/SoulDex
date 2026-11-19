# Dex Browsing (search, sort, filter, compare) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the dex window a toolbar (search box, Sort button, Show button), an "All" row, a two-way compare view for a friend's dex, and a draggable column split, for your own dex and a friend's alike.

**Architecture:** A new pure module `src/Browse.lua` owns the row building, sorting, filtering and compare counts; `View` and `UIFormat` get small additive changes; `UI.lua` gains the toolbar strip, the search state and the split handle. All choices are made in pure code with busted tests; `UI.lua` only wires frames to it.

**Tech Stack:** Lua 5.1, WoW frame API (EditBox, Button), busted, luacheck.

**Spec:** `docs/superpowers/specs/2026-11-10-souldex-design.md`. Task 1 adds section **5.9 Toolbar, search and compare** to it; every later task implements 5.9 and must agree with it.

## Global Constraints

- Every file starts with `local _, ns = ...`; share through `ns`, no new globals.
- `src/Browse.lua` is pure: no WoW API. It goes in `SoulDex.toc` directly after `src\Friends.lua`, and must be `git add`ed.
- Tabs for Lua indentation; lines at most 120 characters; `luacheck .` and `busted` pass after every task.
- Any WoW API newly used is added to `read_globals` in `.luacheckrc`.
- Text read from the search EditBox goes through `ns.Capture.plainString` before use; a value that is not a plain string counts as an empty search.
- Never record or show a wrong name: a compare row never invents a name (a raid creature only you have shows the roster's name).
- A friend's dex carries no dates: nothing in this work may sort or show by date while browsing.
- No Pokémon names anywhere a player sees. Chat output only through `ns.Print`.
- Tabs stay along the bottom of the window. Window size becomes **380 × 300** (was 380 × 280); the list area keeps its present height.
- Do not tag, push or cut a release.

## Review Focus

1. Search text with Lua pattern characters (`%`, `[`, `(`, `.`, `-`): matched as plain text, no error. (Task 3 test.)
2. A saved sort that is junk, or `"recent"` restored while browsing a friend: falls back to the tab's first sort, no error. (Task 2 test.)
3. A mob both warlocks have, but claimed in different zones: it is "shared" everywhere, never "missing" in one zone and "mine" in another. (Task 2 test.)
4. A filter or search that leaves nothing: the right list shows one muted note, never an empty pane or an error; the "Unknown soul" row shows only under the "all" filter. (Tasks 2 and 4 tests.)
5. The "All" row selected and the dex has no places/classes left to show (empty friend dex): the empty-state note shows and no row is selected. (Task 4 test.)

---

### Task 1: Spec section 5.9 and its cross-references

**Files:**
- Modify: `docs/superpowers/specs/2026-11-10-souldex-design.md` (5.1 size bullet, 5.2, 5.3, 5.7 "highlighted green" sentence, new 5.9 after 5.8, section 7 reset line, section 9 list)

- [ ] **Step 1: Add section 5.9** after 5.8, with exactly this content (marked "(changed after 1.7.0, user's call.)" and **[user]**):

  - **Size.** The window is 380 × 300. A 20 px **toolbar strip** sits between the rank progress line and the lists; tabs stay along the bottom; the lists keep their height.
  - **Search.** The strip starts with a search box whose empty text reads "Search all souls". It is on every tab. With 2 or more letters typed, the right list shows every mob, player and raid creature of the dex on screen whose name contains the text (any case, plain text), names that start with it first; each row shows the name, and on the right where it was claimed and `×count`. Clicking a result opens its detail card over the results. Typing on Me, Milestones or Friends switches to Mobs. Escape, clearing the box, picking a tab or clicking a left-list row ends the search. Nothing found: "No soul matching "<text>"."
  - **Sort.** A "Sort: <choice>" button on Mobs and Players; a click steps forward, a right-click back. Mobs: A–Z (default), Most claimed, Newest, Rarest. Players: Most claimed (default), A–Z, Newest. Newest is left out while browsing a friend (their dex has no dates). Rarest orders world bosses, then rares, then elites, then the rest. Ties go by name. The choice is saved per character and per tab. Raids keep their roster order and have no Sort button.
  - **Show.** A "Show: <choice>" button. On your own Mobs tab: All, Rare and elite, Mastered (1 star or more), Not mastered. Your own Players and Raids tabs have none. While browsing a friend, on all three collection tabs: Their dex, Differences, Missing, Only mine, Shared. It is not saved: it returns to the first choice when the window closes or another dex is shown. Sort and Show are hidden during a search.
  - **All row.** The Mobs left list starts with "All zones" and the Players left list with "All classes", each with the total; it is the selection for a fresh window. Selected, the right list holds every soul of that tab once (a mob's count is its total over all zones). The "Unknown soul" row appears only for a single zone under the first Show choice.
  - **Compare (browsing a friend).** A soul they have and you don't is **Missing**, drawn green as before. A soul you have and they don't is **Only mine**, drawn amber (`ffb84d`, the same in every theme), listed among theirs, not clickable. Both having it is **Shared**. A mob counts by name over the whole dex, a player by key, a raid creature by NPC ID, whatever the zone. Differences shows Missing and Only mine together. The right list starts with one line of this tab's totals: "N missing · N only mine · N shared". Left-list rows show "count +N" in green where N souls there are Missing. In a raid's roster, a creature only you have shows its roster name in amber instead of "? ? ?".
  - **Column split.** On Mobs, Players and Raids the line between the lists can be dragged to widen the left list from 124 px (default) up to 200 px; the tooltip is "Drag to resize columns". Saved per character; `/souldex reset` and "Reset window" restore 124. The detail card keeps its place and may cover the widened part of the left list while open. Me and Friends keep their own widths.
  - A filter that leaves nothing: "Nothing here matches."

- [ ] **Step 2: Fix the cross-references.** 5.1: "380 × 280" becomes "380 × 300 (see 5.9)". 5.2 and 5.3: add "see 5.9 for the All row, sorting and filtering". 5.7: after "highlighted green" add "(see 5.9 for the full compare view)". Section 7: `/souldex reset` also resets the column split. 5.1's grip sentence "the layout is unchanged" stays true.

- [ ] **Step 3: Add to section 9** (in-game checks) one bullet per line of the checklist in Task 6 Step 3.

- [ ] **Step 4: Commit** `docs: spec the dex toolbar, search and compare view`

---

### Task 2: `Browse` pure module

**Files:**
- Create: `src/Browse.lua`, `spec/Browse_spec.lua`
- Modify: `SoulDex.toc` (add `src\Browse.lua` after `src\Friends.lua`)

**Interfaces:**
- Consumes: `ns.Dex` (`dex.db.mobs[name].places[zone] = {count, last}`, `dex.db.players[key] = {name, class, count, last}`, `dex.db.raids[npcID] = {instanceID, name, count}`, `dex:stars(entry)`), `ns.View.mobsAt`, `ns.View.playersOf`.
- Produces:
  - `Browse.ALL = "*"` — the left-list value of the All row.
  - `Browse.sorts(tab, browsing) -> {id...}`: Mobs `{"name","count","recent","rarity"}`, Players `{"count","name","recent"}`, anything else `{}`; `browsing == true` removes `"recent"`.
  - `Browse.filters(tab, browsing) -> {id...}`: browsing on Mobs/Players/Raids `{"all","diff","missing","mine","shared"}`; own Mobs `{"all","rare","mastered","unmastered"}`; otherwise `{}`.
  - `Browse.valid(list, id) -> id` if `id` is in `list`, else `list[1]` (nil for an empty list).
  - `Browse.step(list, id, back) -> id`: the next (or previous) entry after `Browse.valid(list, id)`, wrapping.
  - `Browse.label(id, browsing) -> string`: name "A–Z" (en dash `\226\128\147`), count "Most claimed", recent "Newest", rarity "Rarest", all "All" (browsing: "Their dex"), rare "Rare and elite", mastered "Mastered", unmastered "Not mastered", diff "Differences", missing "Missing", mine "Only mine", shared "Shared".
  - `Browse.mobs(dex, place, other) -> rows`: `place == Browse.ALL` gives every mob once with `count` summed and `last` the latest over its places. Row: `{ name, count, classification, stars, last, side, unknown }`. With `other` (your own dex while browsing): `side` is `"missing"` (other has no `mobs[name]`), `"shared"`, or `"mine"` for mobs `other` has (at that place, or anywhere for ALL) that `dex.db.mobs` lacks; a `"mine"` row takes name, count and classification from `other` and has `stars = nil`. Without `other`, `side = nil`. The Unknown-soul row (`unknown = true`) is included for a single place only.
  - `Browse.players(dex, class, other) -> rows`: `{ key, name, class, count, last, side }`, same side rules by key; `class == Browse.ALL` gives everyone.
  - `Browse.apply(rows, filter, sort) -> rows` (a new list): keeps rows by filter (`all`: every row; `rare`: classification is elite, rare, rareelite or worldboss; `mastered`: `stars` ≥ 1; `unmastered`: no stars; `missing`/`mine`/`shared`: that side; `diff`: missing or mine), then orders by sort (`name` ascending; `count` descending; `recent` by `last` descending with nil last; `rarity` worldboss 3, rare and rareelite 2, elite 1, other 0, descending; every tie by name, then key). `sort == nil` keeps the order given (raid rosters). A row with `unknown = true` is kept only under `"all"` and always comes last. Rows without a `side` are dropped by the four compare filters.
  - `Browse.counts(dex, other, tab) -> { missing, mine, shared }` over the whole tab (`"Mobs"` by name, `"Players"` by key, `"Raids"` by NPC ID).

- [ ] **Step 1: Write failing tests** in `spec/Browse_spec.lua`, loading `Themes`… down to `Friends` then `Browse` with `LoadAddonFile` the way `spec/View_spec.lua` builds its `ns` and dexes (reuse its `ctx`/`mob`/`player` helper shapes). Tests and their assertions:
  - `sorts`: `Browse.sorts("Mobs", false)` is `{"name","count","recent","rarity"}`; `("Mobs", true)` has no `"recent"`; `("Players", false)[1] == "count"`; `("Raids", false)` is `{}`.
  - `filters`: own Mobs first is `"all"`, has 4; own Players is `{}`; browsing Raids has 5.
  - `valid` (Review Focus 2): `Browse.valid(Browse.sorts("Mobs", true), "recent") == "name"`; `valid(list, 42) == "name"`; `valid({}, "x") == nil`.
  - `step`: from `"rarity"` forward wraps to `"name"`; from `"name"` back gives `"rarity"`; a junk current id steps from the first.
  - `mobs ALL`: Wolf claimed 2× in Elwynn and 3× in Westfall gives one row, `count == 5`, `last` the later time; no unknown row even when the dex has unknown souls.
  - `mobs sides` (Review Focus 3): friend has Wolf in Elwynn, you have Wolf in Westfall only → the friend's Elwynn row has `side == "shared"`, and `Browse.mobs(friend, "Westfall", you)` has no Wolf row at all. Friend-only Hogger → `"missing"`. Your Boar in Elwynn, absent from the friend → a row `{ name = "Boar", side = "mine", stars = nil }` with your count.
  - `players sides`: same three cases by key; `class == Browse.ALL` returns all classes.
  - `apply filter`: `rare` keeps elite/rare/rareelite/worldboss only; `mastered`/`unmastered` split on stars; `diff` keeps missing and mine, drops shared; a compare filter on rows without sides gives `{}`.
  - `apply unknown` (Review Focus 4): the unknown row survives `"all"` as the last row under every sort, and is absent under `"rare"` and `"diff"`.
  - `apply sort`: `count` descending with name ties; `recent` puts a nil `last` after dated rows; `rarity` orders worldboss, rare, elite, normal; `nil` sort returns the input order; the input list is not modified.
  - `counts`: Mobs `{ missing = 1, mine = 1, shared = 1 }` for the dexes above; Raids counted by NPC ID; Players by key.

- [ ] **Step 2: Run** `busted spec/Browse_spec.lua` — expected: FAIL, `src/Browse.lua` not found.

- [ ] **Step 3: Implement `src/Browse.lua`** to the Interfaces block. `Browse.mobs` for one place starts from `ns.View.mobsAt(dex, place)` and adds `last` and `side`; do not change `View.mobsAt`.

- [ ] **Step 4: Run** `busted spec/Browse_spec.lua` and `luacheck .` — expected: all pass, 0 warnings.

- [ ] **Step 5: Commit** `feat: Browse module for sorting, filtering and comparing dex rows` (include `SoulDex.toc`).

---

### Task 3: `View` additions

**Files:**
- Modify: `src/View.lua` (`View.places`, `View.classes`, `View.raidMobs`, `View.find`)
- Test: `spec/View_spec.lua`

**Interfaces:**
- Produces:
  - `View.places(dex, other)`: unchanged rows, plus `new` on each place row = how many of its mobs `other.db.mobs` lacks (0 without `other`).
  - `View.classes(dex, other)`: plus `new` = players of that class whose key `other.db.players` lacks.
  - `View.raidMobs(dex, instanceID, other)`: each row also has `side`: `"missing"` (dex caught, other has no `raids[npcID]`), `"shared"`, or `"mine"` for a listed creature the dex lacks and `other.db.raids[npcID]` has with the same `instanceID`; a `"mine"` row has `caught = false`, `name` = the roster name, `count` = other's count. No `other` → `side = nil`. Existing fields, `highlight` included, are unchanged.
  - `View.find(dex, text)`: each row also carries `value` (mob: its name; player: its key; raid: its npcID). Order and other fields unchanged.

- [ ] **Step 1: Write failing tests** in `spec/View_spec.lua`:
  - `places new`: friend has Hogger and Wolf in Elwynn, you have Wolf → Elwynn row `new == 1`; without `other`, `new == 0`.
  - `classes new`: same shape by player key.
  - `raidMobs side`: a roster creature only the friend has → `side == "missing"`, `highlight == true`; both → `"shared"`; only you → `caught == false`, `side == "mine"`, `name` equals the roster name, `count` equals yours; an uncaught-by-both row has `side == nil`.
  - `find value`: mob row `value == name`; player row `value == key`; raid row `value == npcID`.
  - `find plain text` (Review Focus 1): `View.find(dex, "%s[(")`, `View.find(dex, "a.")` and `View.find(dex, "a-")` return a table and raise no error; a mob named `Thing (Elite)` is found by `"(el"`.

- [ ] **Step 2: Run** `busted spec/View_spec.lua` — expected: the new tests FAIL, the old ones pass.
- [ ] **Step 3: Implement** the four additions.
- [ ] **Step 4: Run** `busted` and `luacheck .` — expected: all pass.
- [ ] **Step 5: Commit** `feat: compare counts and sides in the dex view model`

---

### Task 4: `UIFormat` rows for the new views

**Files:**
- Modify: `src/UIFormat.lua`
- Test: `spec/UIFormat_spec.lua`

**Interfaces:**
- Consumes: Task 2 rows (`side`), Task 3 rows (`new`, `value`), `ns.Browse.ALL`, `ns.Browse.label`.
- Produces:
  - `F.MINE = "ffb84d"`.
  - `F.placeRows(rows, selected, total, browsing)`: `total` is the dex's unique-mob count. When `rows` has at least one place, the first output row is `{ text = "All zones", right = tostring(total), value = ns.Browse.ALL, selected = selected == ns.Browse.ALL }`. With `browsing`, a place row with `new > 0` has `right = count .. " +" .. new` and `rightColor = C.GOOD`.
  - `F.classRows(rows, selected, classColors, classNames, total, browsing)`: same All row, text "All classes", `total` = unique players; same `+new`.
  - `F.mobRows(rows)`, `F.playerRows(rows)`, `F.raidMobRows(rows)`: a row with `side == "missing"` (or the old `highlight`) is `C.GOOD`; `side == "mine"` is `F.MINE` with `value = nil` (not clickable); a raid row with `side == "mine"` shows its name (with the skull for a boss), not "? ? ?".
  - `F.findRows(found, classNames) -> rows`: per result `{ text = name, right = <where> .. " " .. ×count, value = { kind = row.kind, id = row.value } }`; a player's `where` is its localized class name (class token title-cased without `classNames`, "player" when it has none); a missing `where` leaves just the count.
  - `F.compareLine(counts) -> row`: `{ text = "<missing> missing · <mine> only mine · <shared> shared", wrap = true }` with the first number and word wrapped in `|cff<C.GOOD>…|r`, the second in `|cff<F.MINE>…|r`, the rest `C.MUTED`; not clickable.
  - `F.toolLabel(kind, id, browsing) -> string`: `"Sort: " .. Browse.label(id)` for `kind == "sort"`, `"Show: " .. Browse.label(id, browsing)` for `"show"`.
  - `F.emptyNote(search) -> row`: `F.note('No soul matching "' .. search .. '".')` with a search text, else `F.note("Nothing here matches.")`.

- [ ] **Step 1: Write failing tests** in `spec/UIFormat_spec.lua`:
  - `placeRows All`: two places and `total = 7` → `out[1].text == "All zones"`, `out[1].right == "7"`, `out[1].value == "*"`; `selected = "*"` marks only it.
  - `placeRows empty` (Review Focus 5): `F.placeRows({}, "*", 0)` is `{}`, and `F.pick({}, "place", "*") == nil`.
  - `placeRows new`: browsing, `count = 14, new = 3` → `right == "14 +3"`, `rightColor == C.GOOD`; `new = 0` → `right == "14"`, no `rightColor`; not browsing → `"14"` even with `new = 3`.
  - `classRows All`: first row "All classes" with the total.
  - `mobRows sides`: missing → `color == C.GOOD` and clickable; mine → `color == F.MINE`, `value == nil`; shared → its normal colour.
  - `raidMobRows mine`: `{ caught = false, side = "mine", name = "Lucifron", boss = true }` → text contains "Lucifron", colour `F.MINE`, `value == nil`; a plain uncaught row is still "? ? ?".
  - `findRows`: mob with `where = "Elwynn Forest +1"`, count 12 → right is `"Elwynn Forest +1 ×12"`, `value` is `{ kind = "mob", id = "Hogger" }`; player `where = "ROGUE"` with `classNames.ROGUE = "Rogue"` → right starts with "Rogue".
  - `compareLine`: counts `{ missing = 61, mine = 87, shared = 140 }` → text contains "61 missing", "87 only mine", "140 shared" and both colour codes.
  - `toolLabel`: `("sort", "name")` is `"Sort: A–Z"`; `("show", "all", true)` is `"Show: Their dex"`.
  - `emptyNote` (Review Focus 4): with `"zz"` → text `No soul matching "zz".`; without → "Nothing here matches."

- [ ] **Step 2: Run** `busted spec/UIFormat_spec.lua` — expected: new tests FAIL.
- [ ] **Step 3: Implement.** `UIFormat` loads after `Browse`, so it may read `ns.Browse` at file scope. Update the two existing callers' argument lists only in Task 5.
- [ ] **Step 4: Run** `busted` and `luacheck .` — expected: all pass (existing `placeRows`/`classRows` tests updated for the All row where they pass a non-empty list).
- [ ] **Step 5: Commit** `feat: rows for the All view, search results and the compare view`

---

### Task 5: The toolbar, search, sort, show and the column split in the window

**Files:**
- Modify: `src/UI.lua`, `src/UIList.lua` (`List:setWidth`), `src/Settings.lua` (`Settings.split`), `.luacheckrc` (only if a new API is used)
- Test: `spec/Settings_spec.lua`, `spec/UI_spec.lua`

**Interfaces:**
- Consumes: everything Tasks 2–4 produce; `ns.Capture.plainString(v)`.
- Produces:
  - `Settings.SPLIT_MIN, Settings.SPLIT_MAX, Settings.SPLIT_DEFAULT = 124, 200, 124`; `Settings.split(value) -> number`: a number is rounded and clamped to the limits; anything else (nil, text, NaN) gives 124.
  - `List:setWidth(width)`: resizes the scroll frame, its child and every pooled row, and stores `self.width` (rows made later use it; the next `set` re-lays wrapped text).
  - `UI.setSearch(text)` and `UI.search() -> string` (for tests and `/souldex find` reuse later): sets the search text as if typed.
  - Saved state: `ns.db.window.sort = { Mobs = id, Players = id }`, `ns.db.window.split = number`. Read through `Browse.valid` and `Settings.split`, so junk is harmless.

- [ ] **Step 1: Write failing tests.**
  - `spec/Settings_spec.lua`: `Settings.split(150) == 150`; `split(90) == 124`; `split(999) == 200`; `split(150.6) == 151`; `split(nil)`, `split("x")` and `split(0/0)` are 124.
  - `spec/UI_spec.lua` (same stub style as the file's existing tests; add `EditBox` methods `GetText`/`SetText`/`ClearFocus` to the stub as needed):
    - the window frame is sized 380 × 300;
    - an EditBox exists; running its `OnTextChanged` with text "ho" (stub `GetText` returns it) makes `ns.UI.search() == "ho"`, and with a non-string from `GetText` makes it `""`;
    - `UI.setSearch("ho")` on the Me tab leaves `UI.currentTab() == "Mobs"`; `UI.selectTab("Players")` then makes `UI.search() == ""`;
    - clicking the Sort button on Mobs once saves `ns.db.window.sort.Mobs == "count"`, and its label reads "Sort: Most claimed";
    - with `ns.db.window.sort = { Mobs = "recent" }`, `UI.showDex(friendDex, "Morwen")` then drawing Mobs raises no error and the Sort label is "Sort: A–Z" (Review Focus 2);
    - the Show button steps to "Show: Rare and elite" on your own Mobs tab, and reads "Show: Their dex" again after `UI.showDex(friendDex, "Morwen")`; hiding and reopening the window resets it to "Show: All";
    - `ns.db.window.split = 180` before the window is built: the left list is 180 wide; `UI.resetWindow()` clears `ns.db.window.split` and the left list is 124 wide again;
    - opening on an empty dex with `state.sel.Mobs` at the All value raises no error (Review Focus 5).

- [ ] **Step 2: Run** `busted spec/Settings_spec.lua spec/UI_spec.lua` — expected: new tests FAIL.

- [ ] **Step 3: Implement `Settings.split` and `List:setWidth`.**

- [ ] **Step 4: Implement the layout in `src/UI.lua`.**
  - `HEIGHT = 300`, new `TOOLBAR_H = 20`; `BODY_H` subtracts `TOOLBAR_H` (it stays 208); the body's top offset becomes `PAD + TITLE_H + 6 + TOOLBAR_H`. Nothing else moves; tabs stay at `BOTTOMLEFT`.
  - `buildToolbar()`: a frame at `TOPLEFT PAD, -(PAD + TITLE_H + 5)`, `BODY_W × 16`. Left to right: the search EditBox (fills what the buttons leave; `SetAutoFocus(false)`, `SetMaxLetters(40)`, `GameFontHighlightSmall`, backdrop `TAB_BG`/`BUTTON_EDGE`, a `MUTED` font string "Search all souls" shown while the text is empty), a Sort button 98 wide, a Show button 104 wide, 3 px gaps, each `UI.button(..., 16)` with `RegisterForClicks("LeftButtonUp", "RightButtonUp")` (right-click steps back).
  - EditBox scripts: `OnTextChanged` → `UI.setSearch(ns.Capture.plainString(self:GetText()) or "")`; `OnEscapePressed` → clear the text and the focus; `OnEnterPressed` → clear the focus.
  - Sort/Show are shown only when the tab's `Browse.sorts` / `Browse.filters` list is non-empty and no search is active.

- [ ] **Step 5: Implement the state and drawing in `src/UI.lua`.**
  - `state.search = ""`, `state.filter = nil` (nil = first choice). A search is active when the trimmed text has `ns.View.FIND_MIN` letters or more.
  - `UI.setSearch(text)`: stores it, keeps the EditBox text in step, closes the detail card, switches to Mobs when the tab is not a collection tab and the search is active, then `draw("tab")`.
  - `UI.selectTab`, `selectLeft`, `UI.showDex` and the frame's `OnHide` clear the search; `UI.showDex` and `OnHide` also reset `state.filter`.
  - `drawLists`:
    - searching → right rows are `F.findRows(View.find(dex, text), LOCALIZED_CLASS_NAMES_MALE)`, or `{ F.emptyNote(text) }`; the left list is drawn as usual.
    - Mobs → left `F.placeRows(View.places(dex, other()), sel, dex:uniqueMobs(), browsing)`; right `F.mobRows(Browse.apply(Browse.mobs(dex, sel, other()), filter, sort))`.
    - Players → the same with `View.classes`, `dex:uniquePlayers()`, `Browse.players`, `F.playerRows`.
    - Raids → `F.raidMobRows(Browse.apply(View.raidMobs(dex, id, other()), filter, nil))`, the TBD note still first.
    - `filter = Browse.valid(Browse.filters(tab, browsing), state.filter)`; `sort = Browse.valid(Browse.sorts(tab, browsing), saved sort for the tab)`.
    - no rows left after `apply` → `{ F.emptyNote() }` (the existing empty-dex notes stay for a dex with nothing on that tab).
    - browsing and not searching → `F.compareLine(Browse.counts(dex, other(), tab))` is inserted as the first right row.
  - Right-list clicks: a search result (`value` is a table) opens the card of its kind: `detailCard` takes the kind's tab ("mob" → Mobs with place nil, "player" → Players, "raid" → Raids) and `state.detail` records that tab plus `search = true`; `draw` keeps such a card open while the search is active. Other clicks behave as today, except `View.mobDetail` gets place nil when the selection is `Browse.ALL`.
  - Sort click: `ns.db.window.sort[tab] = Browse.step(list, current, back)`, then `draw("select")`. Show click: `state.filter = Browse.step(...)`, then `draw("select")`.

- [ ] **Step 6: Implement the column split in `src/UI.lua`.**
  - The split in use is `Settings.split(ns.db.window.split)` on Mobs, Players and Raids, and stays `LEFT_W` (124) for Me; Friends keeps `FRIENDS_LEFT_W`.
  - `applySplit(w)`: `leftList:setWidth(w)`, `rightList:setWidth(BODY_W - (w + 5))`, re-anchor `rightList.frame` at `w + 5`; `draw` places the divider at `w + 2` on collection tabs. The detail pane is not moved.
  - A 7 px wide invisible `Button` over the divider, shown on collection tabs only: `OnMouseDown` records the cursor x, the split and `frame:GetEffectiveScale()`; `OnUpdate` while held sets the split to `Settings.split(start + (x - x0) / effectiveScale)` and redraws with `"refresh"` when it changed; `OnMouseUp` saves `ns.db.window.split`. Tooltip "Drag to resize columns".
  - `UI.resetWindow()` also sets `ns.db.window.split = nil` and applies 124.

- [ ] **Step 7: Run** `busted` and `luacheck .` — expected: all pass, 0 warnings.

- [ ] **Step 8: Commit** `feat: search, sort, filter, compare view and a draggable column split in the dex window`

---

### Task 6: Changelog, final checks, in-game checklist

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add under `## [Unreleased]`:**
  - "Search box in the window: type part of a name to find any soul in the dex on screen, your own or a friend's."
  - "Sort and Show buttons on the Mobs and Players lists: order by name, most claimed, newest or rarest, and show only rares and elites or only mastered souls. Your sort is remembered."
  - "\"All zones\" and \"All classes\" rows list a whole collection at once."
  - "Browsing a friend's dex now compares both ways: what you're missing in green, what only you have in amber, with totals, and Show can narrow it to differences, missing, only yours or shared."
  - "Drag the line between the two lists to give zone names more room. The window is slightly taller to fit the new toolbar."

- [ ] **Step 2: Run** `luacheck .`, `busted`, then `scripts/build.sh --no-install` — expected: 0 warnings, 0 failures, a zip in `.release/` that contains `src/Browse.lua`.

- [ ] **Step 3: Hand the user this in-game checklist** (the same lines go in spec section 9, Task 1 Step 3):
  - `/souldex`: the window is a little taller; a strip under the title holds "Search all souls", "Sort: A–Z" and "Show: All"; tabs are still along the bottom; nothing overlaps the resize grip.
  - Mobs opens on "All zones" with every mob listed once; clicking a zone works as before.
  - Type two letters: results from mobs, players and raids appear with where and count; click one: its card opens; Escape clears the box and does not close the window; a second Escape closes the window.
  - Typing in the box does not trigger key bindings (no movement, no bars) and the box loses focus on Enter.
  - Click Sort through all four choices, right-click steps back; `/reload`: the choice is kept. Show is back on "All".
  - Players: "All classes" first; Sort has three choices, no Show button. Raids: no Sort, no Show.
  - Browse a friend's dex: the first right row gives the three totals in green, amber and grey; zones with something new read "14 +3" in green; "Show: Differences / Missing / Only mine / Shared" each change the list; amber rows do nothing on click; Sort has no "Newest".
  - On a friend's raid, a creature only you have shows its name in amber.
  - Drag the line between the lists right: zone names get more room, up to a limit; `/reload` keeps it; `/souldex reset` restores it. Open a card with the left list widened: it covers part of the left list and closes normally.
  - All four colour themes: the toolbar follows the theme; amber stays amber.
  - Window at 60% and 160% size: the toolbar scales with it and the search box is still usable.

- [ ] **Step 4: Commit** `docs: changelog for dex browsing`
