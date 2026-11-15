# Rank Emblems Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the game's Soul Shard icon everywhere SoulDex shows it with eight original emblems, one per warlock rank, that grow from a dull sliver to the full fel-lit emblem.

**Architecture:** One HTML/SVG source page draws all eight emblems from layers taken from the project's own `docs/curseforge/source/shard.svg`. A dev-only script renders them with headless Chrome and converts them to 64 × 64 TGA files in `art/`, which are committed and shipped. `Ranks.emblem(index)` (pure) gives the texture path; the window, the Me crest, both popups and the detail card ask it instead of naming a game icon.

**Tech Stack:** Lua 5.1, busted, luacheck; headless Chrome and Python 3 with Pillow for the art build only (never needed to build or test the addon).

**Spec:** `docs/superpowers/specs/2026-11-10-souldex-design.md` (5.1, 5.5, 5.8, 6.2, 6.6, 7a, 9). Task 4 brings it into line with the code.

## What the audit found

The addon zip contains **no Blizzard art**: no image files ship at all. Every icon is a path the player's own client resolves (`Interface\Icons\...`), which is how addons normally use game icons. The store images in `docs/curseforge/images/` are rendered from the project's own HTML and SVG.

Game art referenced by path today:

| Where | What | This plan |
|-------|------|-----------|
| `UIFormat.lua` `F.SHARD_ICON`, `Toast.lua` `SHARD_ICON_FILE` / `shardIcon` | Soul Shard gem: title bar, Me crest, both popups, card fallback | **Replaced** |
| `UIFormat.lua` `TYPE_ICONS`, `PLAYER_ICON` | creature-type and crossed-swords icons on the card | Kept |
| `UIFormat.lua` `STAR`, `SKULL`, `CHECK` | raid-target star and skull, ready-check tick | Kept |
| `UI.lua` gear button | `INV_Misc_Gear_01` | Kept |
| `Interface\Buttons\WHITE8X8`, `PlaySound` ids | flat fill, sounds | Kept |

The kept ones are path references only; replacing them is a separate plan if wanted.

## Global Constraints

- Start a branch `rank-emblems` from `main`. The current `forever-raids` branch has uncommitted work that is not part of this.
- `luacheck .` and `busted` pass before every commit.
- Every file starts with `local addonName, ns = ...` or `local _, ns = ...`; no new globals.
- Pure modules call no WoW API. `Ranks` stays pure: a path string is not an API call.
- Tabs for Lua indentation.
- The art is original: drawn only from shapes in `docs/curseforge/source/shard.svg`. No Blizzard art, no Pokémon names or art.
- Brand voice: soul-hunter, warlock, not sentimental.
- Never hand-edit `art/*.tga`; change `scripts/art/emblem.html` and run `scripts/art/render.sh`.
- New files must be `git add`ed or the build leaves them out.
- Commit with the GitHub no-reply address; no local paths in docs.
- `scripts/build.sh` does not work inside a git worktree.

## Review Focus

1. **A rank is added to `Ranks.LIST` with no art file**: the player sees a green square. Expected: tests fail first. Pinned in Task 1 (`spec/Art_spec.lua`).
2. **A bad rank index** (nil, 0, 9, 2.5, a string) reaches `Ranks.emblem`: expected a valid path for the nearest real rank, never nil. Pinned in Task 2.
3. **The addon folder has another name** (a GitHub zip unpacks as `SoulDex-main`): expected the art still loads, so the path uses the name the game passes in. Pinned in Task 2.
4. **A friend's dex sends a broken score**: expected the Initiate emblem, as the rank already falls back to 0. Pinned in Task 2.
5. **A popup is shown with no emblem passed** (a caller this plan missed): expected the Initiate emblem, not an empty square. Guarded in Task 3 (`emblem or ns.Ranks.emblem(1)`); game code, so it is checked in game.

---

### Task 1: Draw the eight emblems and build the textures

**Files:**
- Create: `scripts/art/emblem.html`, `scripts/art/render.sh`, `scripts/art/to_tga.py`
- Create (generated): `art/rank1.tga` … `art/rank8.tga`, `docs/curseforge/images/rank-emblems.png`
- Test: `spec/Art_spec.lua`

**Interfaces:**
- Produces: `art/rank<N>.tga` for N = 1..8; each 64 × 64, 32-bit, uncompressed (TGA image type 2), transparent background.

- [ ] **Step 1: Write the failing test** in `spec/Art_spec.lua`

```lua
describe("Art", function()
	local ns = LoadAddonFile("src/Ranks.lua")

	local function bytes(path)
		local file = io.open(path, "rb")
		if not file then
			return nil
		end
		local data = file:read("*a")
		file:close()
		return data
	end

	it("has a 64x64 32-bit uncompressed TGA for every rank", function()
		for index in ipairs(ns.Ranks.LIST) do
			local path = "art/rank" .. index .. ".tga"
			local data = bytes(path)
			assert.is_truthy(data, path .. " is missing")
			assert.equal(0, data:byte(1), path .. ": no id field")
			assert.equal(2, data:byte(3), path .. ": uncompressed true colour")
			assert.equal(64, data:byte(13) + data:byte(14) * 256, path .. ": width")
			assert.equal(64, data:byte(15) + data:byte(16) * 256, path .. ": height")
			assert.equal(32, data:byte(17), path .. ": bits per pixel")
			assert.is_true(#data >= 18 + 64 * 64 * 4, path .. ": pixel data")
		end
	end)

	it("has a transparent corner and something drawn", function()
		for index in ipairs(ns.Ranks.LIST) do
			local data = bytes("art/rank" .. index .. ".tga")
			assert.equal(0, data:byte(18 + 4), "rank " .. index .. ": first pixel's alpha")
			local drawn = false
			for pixel = 0, 64 * 64 - 1 do
				if data:byte(18 + pixel * 4 + 4) > 0 then
					drawn = true
					break
				end
			end
			assert.is_true(drawn, "rank " .. index .. " is empty")
		end
	end)

	it("has no art for ranks that don't exist", function()
		assert.is_nil(bytes("art/rank" .. (#ns.Ranks.LIST + 1) .. ".tga"))
	end)
end)
```

- [ ] **Step 2: Run it.** `busted spec/Art_spec.lua` → FAIL, "art/rank1.tga is missing".

- [ ] **Step 3: Write `scripts/art/emblem.html`**

One page, one inline SVG with `viewBox="0 0 200 200"`, transparent page background, no outside files or fonts. Query string: `?rank=N` (1..8, default 8) draws one emblem filling the window; `?sheet` draws the review sheet (Step 6). Copy the gradients, filters and shapes from `docs/curseforge/source/shard.svg` and put each layer in its own `<g>`, shown by rank:

| Rank | Name | Layers drawn |
|------|------|--------------|
| 1 | Initiate | The shard only, at 60 % scale, its faces greyed (`#8f84a6` → `#332b42`), no glow |
| 2 | Acolyte | Full-size violet shard (the `faceL` / `faceR` faces and sheen) on a soft violet glow (`#4a1a8f`) |
| 3 | Soul Thief | + the dark disc and a thin plain iron band (stroke 5, no rivets) |
| 4 | Shardbinder | + the full band (keyline, bevel, lit and shadowed rims) with its eight rivets |
| 5 | Reaper | + three ring spikes: bottom and both sides |
| 6 | Soul Harvester | + all five spikes of `shard.svg`, the fel-lit inner rim and the fel light on the shard's lower edges |
| 7 | Soul Tyrant | + the fel bolts crackling off the shard and their glowing ends; eight spikes, evenly round the ring |
| 8 | Lord of Souls | + the arcs across the shard's face, the outer fel aura, and the top three spikes drawn 1.5 × taller as a crown |

Each rank keeps everything the rank below it has. All drawing stays inside the 200 × 200 box with nothing closer than 4 units to an edge (rank 8's crown and aura set the scale; scale the whole group to fit). The shape must still read at 14 px: the steps a player sees are sliver → shard → ring → spikes → green.

- [ ] **Step 4: Write `scripts/art/to_tga.py`**

`python3 scripts/art/to_tga.py <in.png> <out.tga>`: open with Pillow, convert to RGBA, resize to 64 × 64 with `Image.LANCZOS`, save as TGA with no compression (Pillow's default; do not pass `compression`). Exit non-zero with a one-line message when Pillow is missing.

- [ ] **Step 5: Write `scripts/art/render.sh`**

Find the browser the way `docs/curseforge/source/render.sh` does (same candidate list, same `cygpath` handling). For N in 1..8: shoot `emblem.html?rank=N` at 256 × 256 with `--default-background-color=00000000` into a temp folder, then run `to_tga.py` into `art/rankN.tga`. Then shoot `emblem.html?sheet` at 1200 × 420 into `docs/curseforge/images/rank-emblems.png`. Remove the temp folder. `chmod +x`.

- [ ] **Step 6: The review sheet** (`?sheet` in `emblem.html`)

On the window's background colour `#14101c`: one column per rank, with the rank's name in `#9dff3a` over the emblem at 128 px, then at 52, 38 and 14 px (the crest, popup and title-bar sizes).

- [ ] **Step 7: Build.** `scripts/art/render.sh` → eight `art/rank*.tga` files and the sheet.

- [ ] **Step 8: Run the test.** `busted spec/Art_spec.lua` → PASS.

- [ ] **Step 9: Look at the sheet and show the user.** Read `docs/curseforge/images/rank-emblems.png`. Fix anything clipped, anything that does not read at 14 px, and any two neighbouring ranks that look the same at 38 px; rebuild. Then show the sheet to the user and **wait for their approval of the art** before Task 3.

- [ ] **Step 10: Commit**

```bash
git add scripts/art art spec/Art_spec.lua docs/curseforge/images/rank-emblems.png
git commit -m "feat: original emblem art for each rank"
```

---

### Task 2: `Ranks.emblem`

**Files:**
- Modify: `src/Ranks.lua`
- Test: `spec/Ranks_spec.lua`

**Interfaces:**
- Produces: `Ranks.emblem(index) -> string`, the texture path `Interface\AddOns\<addon folder>\art\rank<N>.tga`. `Ranks.of(score).emblem` is the same path for that rank.

- [ ] **Step 1: Write the failing tests** (add to `spec/Ranks_spec.lua`, using that file's existing `Ranks`)

```lua
	it("names an emblem texture for each rank", function()
		assert.equal("Interface\\AddOns\\SoulDex\\art\\rank1.tga", Ranks.emblem(1))
		assert.equal("Interface\\AddOns\\SoulDex\\art\\rank8.tga", Ranks.emblem(8))
		assert.equal(Ranks.emblem(4), Ranks.of(1000).emblem)
		assert.equal(Ranks.emblem(8), Ranks.of(99999).emblem)
	end)

	it("gives the nearest real emblem for a bad index", function()
		assert.equal(Ranks.emblem(1), Ranks.emblem(nil))
		assert.equal(Ranks.emblem(1), Ranks.emblem("3"))
		assert.equal(Ranks.emblem(1), Ranks.emblem(0))
		assert.equal(Ranks.emblem(1), Ranks.emblem(-2))
		assert.equal(Ranks.emblem(2), Ranks.emblem(2.9))
		assert.equal(Ranks.emblem(#Ranks.LIST), Ranks.emblem(#Ranks.LIST + 1))
		assert.equal(Ranks.emblem(1), Ranks.of(nil).emblem)
		assert.equal(Ranks.emblem(1), Ranks.of("lots").emblem)
	end)

	it("finds the art under whatever folder the addon was loaded from", function()
		local other = {}
		loadfile("src/Ranks.lua")("SoulDex-main", other)
		assert.equal("Interface\\AddOns\\SoulDex-main\\art\\rank3.tga", other.Ranks.emblem(3))
	end)
```

- [ ] **Step 2: Run.** `busted spec/Ranks_spec.lua` → FAIL, `emblem` is nil.

- [ ] **Step 3: Implement** in `src/Ranks.lua`: change the first line to `local addonName, ns = ...`; add `Ranks.emblem(index)` (not a number → 1; floor; clamp to 1..`#Ranks.LIST`); set `out.emblem` in `Ranks.of`; add `emblem` to the comment that lists what `Ranks.of` returns.

- [ ] **Step 4: Run.** `busted spec/Ranks_spec.lua` → PASS; `luacheck .` → clean.

- [ ] **Step 5: Commit**

```bash
git add src/Ranks.lua spec/Ranks_spec.lua
git commit -m "feat: emblem texture path for each rank"
```

---

### Task 3: Show the emblems; remove the game's Soul Shard icon

**Files:**
- Modify: `src/UIFormat.lua`, `src/UI.lua`, `src/UIDetail.lua`, `src/Toast.lua`, `src/Capture.lua`, `.luacheckrc`
- Test: `spec/UIFormat_spec.lua`, `spec/Capture_spec.lua`, `spec/Art_spec.lua`

**Interfaces:**
- Consumes: `Ranks.emblem(index)`, `Ranks.of(score).emblem` (Task 2).
- Produces: `F.typeIcon(creatureType) -> string | nil` (nil for an unknown type); `Toast.show(result, info, ctx, color, emblem)`; `F.SHARD_ICON`, `Toast.SHARD_ICON_FILE` and `Toast.shardIcon` no longer exist.

- [ ] **Step 1: Change the tests**

`spec/UIFormat_spec.lua`: in the mob-card test that asserts `F.SHARD_ICON` for a mob with no creature type, assert `assert.is_nil(card.icon)` instead, and add:

```lua
			assert.is_nil(F.typeIcon(nil))
			assert.is_nil(F.typeIcon("Aberration"))
			assert.is_nil(F.SHARD_ICON)
```

`spec/Capture_spec.lua`: delete the test "finds the shard icon without the removed GetItemIcon". In the test that replaces `ns.Toast.show` with `function(result) shown[#shown + 1] = result end`, record the fifth argument too and assert it equals `ns.Ranks.of(<that test's dex>:score()).emblem`.

`spec/Art_spec.lua`, add:

```lua
	it("names the game's Soul Shard icon nowhere in the addon", function()
		for line in io.lines("SoulDex.toc") do
			local path = line:match("^(src\\.+%.lua)%s*$")
			if path then
				path = path:gsub("\\", "/")
				assert.is_nil(bytes(path):find("Gem_Amethyst", 1, true), path)
			end
		end
	end)
```

- [ ] **Step 2: Run.** `busted` → the changed and new tests FAIL.

- [ ] **Step 3: `src/UIFormat.lua`.** Remove `F.SHARD_ICON`. `F.typeIcon` returns nil when the type has no icon. Update the comment above `TYPE_ICONS`: unknown types and other client languages get the rank emblem, set by the window.

- [ ] **Step 4: `src/Toast.lua`.** Remove `Toast.SHARD_ICON_FILE` and `Toast.shardIcon`. `build` no longer sets the icon's texture. `Toast.show` takes a fifth parameter `emblem` and sets `frame.icon:SetTexture(emblem or ns.Ranks.emblem(1))`. `Toast.showRank(rank)` sets `frame.icon:SetTexture(rank.emblem or ns.Ranks.emblem(rank.index))`. Update both functions' comments.

- [ ] **Step 5: `src/Capture.lua`.** The local `popup` gains the dex (`popup(db, dex, result, entry, rank)`; update its one caller in `afterCatch`) and passes `ns.Ranks.of(dex:score()).emblem` as the fifth argument of `ns.Toast.show`. The score already includes this catch, so a catch that ranks you up shows the new emblem in both popups.

- [ ] **Step 6: `src/UI.lua`.**
  - Title bar: keep the emblem texture in a file-level local (beside `chip`); drop its `SetTexCoord` crop and the "Soul Shard's own icon" comment. Where the refresh works out `local rank = ns.Ranks.of(dex:score())` for the chip, also `emblem:SetTexture(rank.emblem)`, so it follows the dex on screen like the chip does.
  - Me crest: drop `crest.icon`'s `SetTexture` and `SetTexCoord` from `buildMe`; in `drawMe` add `crest.icon:SetTexture(rank.emblem)`.
  - `detailCard`: when the card it is about to return has no `icon`, set `card.icon = ns.Ranks.of(dex:score()).emblem` and `card.ownArt = true`.

- [ ] **Step 7: `src/UIDetail.lua`.**
  - `Pane:setCard`: `p.icon:SetTexture(card.icon or ns.Ranks.emblem(1))`; set the tex coords to `0, 1, 0, 1` when `card.ownArt`, else `0.08, 0.92, 0.08, 0.92` (move the crop here from where the pane is built).
  - Where the pane is built: add `p.iconBack`, a texture on the same rectangle as `p.icon`, layer `ARTWORK` sub-level 1, filled `14101c` with `UI.fill`, so the border colour does not show through the emblem's transparent corners.

- [ ] **Step 8: `.luacheckrc`.** Remove `"GetItemIcon"` from `read_globals` (nothing uses it now). Keep `"C_Item"`: `Capture.lua` still uses it.

- [ ] **Step 9: Run.** `busted` → all PASS; `luacheck .` → clean; `grep -rn "Gem_Amethyst\|SHARD_ICON\|shardIcon" src spec` → only the `Gem_Amethyst` guard in `spec/Art_spec.lua` and `assert.is_nil(F.SHARD_ICON)`.

- [ ] **Step 10: Commit**

```bash
git add src spec .luacheckrc
git commit -m "feat: show the rank emblem in place of the Soul Shard icon"
```

---

### Task 4: Spec, docs, changelog and the in-game hand-off

**Files:**
- Modify: `docs/superpowers/specs/2026-11-10-souldex-design.md`, `CLAUDE.md`, `CHANGELOG.md`

- [ ] **Step 1: Update the spec.** Mark each change "(changed after 1.2.4: rank emblems.) **[user]**".
  - 5.1: the title bar starts with the **rank emblem** of the dex on screen. Replace the bullet "A custom emblem texture is not shipped yet …" with: the emblems ship in `art/` as 64 × 64 32-bit uncompressed TGA, original art, one per rank; no game art stands in for them.
  - 5.5: the card's icon for other languages and unknown types is the rank emblem of the dex on screen, on a dark backing, uncropped.
  - 5.8: the crest shows the rank's emblem.
  - 6.2: the soul popup's icon is your rank emblem after the claim; the rank-up popup's is the new rank's.
  - 6.6: add an "Emblem" column to the table using the "Layers drawn" wording of Task 1, and the rule that a new rank needs a new `art/rank<N>.tga` (`spec/Art_spec.lua` enforces it).
  - 7a: `art/` (shipped, generated) and `scripts/art/` (source and build, not shipped); `Ranks.emblem`.
  - 9, under the UI rework checks, add:
    - Title bar, Me crest, both popups and the card of a mob with no known type show the emblem: no green square, not upside down, not mirrored, no dark or coloured box round it.
    - `/souldex` on a low and a high character (or a friend's dex): the emblem differs by rank and the title-bar one changes while browsing a friend.
    - Ranking up: both popups show the new rank's emblem.
    - The 14 px title-bar emblem is recognisable.
    - If every emblem is a green square, the client does not read this TGA form: report it.

- [ ] **Step 2: `CLAUDE.md`.** In Layout add: `art/` holds the rank emblems, generated from `scripts/art/emblem.html` by `scripts/art/render.sh` (needs Chrome and Python 3 with Pillow): never hand-edit. Add the command to the Commands table. In Code rules add: a new rank needs its emblem.

- [ ] **Step 3: `CHANGELOG.md`** under `## [Unreleased]`:

```markdown
- Your rank now has its own emblem, eight in all, from a dull sliver to a fel-crowned shard. It replaces the Soul Shard icon in the window, on the Me tab and in the popups.
```

- [ ] **Step 4: Verify.** `luacheck .` and `busted` pass. From a normal checkout (not a worktree), `scripts/build.sh --no-install`, then `unzip -l .release/*.zip | grep "art/rank"` → eight files.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/specs/2026-11-10-souldex-design.md CLAUDE.md CHANGELOG.md
git commit -m "docs: rank emblems in the spec, changelog and project notes"
```

- [ ] **Step 6: Hand off.** Build and install (`scripts/build.sh`), then give the user the section 9 checks added in Step 1 as a numbered list with what they should see, and wait for their report. Do not tag or push.
