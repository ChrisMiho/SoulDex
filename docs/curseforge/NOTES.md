# CurseForge page refresh for 1.4.0

What changed on the page, which images are drawn, and the in-game screenshots that
should replace them. Upload steps are in `SUBMISSION.md`.

## What changed

- `description.md`
  - Intro: open with `/dex`, a key binding or the addon list by the minimap.
  - The hunt: dungeon souls get their real names, read through a hidden whisper to
    yourself (a boss drained mid-fight is still Unknown).
  - The raids: The Barrow Deeps and Hyjal Summit are listed, rosters still to come.
  - The trophies: points on the popup; mastery stars and rank-ups get their own popups.
  - The climb: rank emblems, milestones from First Harvest to Raid Reaper, the Me tab's
    records.
  - New section, **The grimoire**: the switches, SIZE (60–160%), the Settings > AddOns
    page and the key binding.
  - Commands table: every command `/dex help` lists (`src/Init.lua`), and a pointer to `/dex help`.
  - One line on the experimental "Boss names after the fight (test)" option.
  - Image links 1–6 are now placeholders (`MOBS_IMAGE_URL` … `SETTINGS_IMAGE_URL`), since
    all six images are new uploads. The banner keeps its current URL (unchanged).
- `README.md`: the same additions, and the sixth image.
- `SUBMISSION.md`: six gallery images; title 6 is **The grimoire — Bend it to your will**.
- `source/`: the window, popup and Me crest icons now show the real rank emblem
  (`scripts/art/emblem.html`, the art `art/rank<N>.tga` is made from) instead of a
  purple placeholder; Forever's raids are on the Raids list; new `feature-6-settings.html`;
  `render.sh` renders it. Logo, icons and banner are unchanged.

## Real or mockup

No image is an in-game screenshot. All six feature images are **mockups**, drawn in
HTML from the layout and colours in `src/UI*.lua`, `src/Toast.lua`, `src/Options.lua`
and `src/Init.lua`, and each says "Illustration" in its corner. The banner, logo, icons
and `rank-emblems.png` are brand art, not the UI.

Places where a mockup is only an approximation:

- Fonts: the game's own font is drawn as a serif (window) or Arial (chat).
- Image 6: the tick boxes stand in for the game's check-box art; the addon-list entry
  above the tooltip is a sketch of the dropdown's row.
- Image 2: how the game cuts off a long raid name ("The Barrow De…") is a guess.
- Mob names, counts, dates and players are made up.

## Screenshots to take

Alt+Z hides the rest of the UI; open SoulDex first, then crop. Use a character with a
fair dex (Shardbinder or higher) so the numbers look lived-in.

| Replaces | Window, tab and state | You should see |
|---|---|---|
| `feature-1-mobs.png` | SoulDex, **Mobs** tab, a zone selected, an **elite** clicked open | Trophy card in yellow: rank emblem, name, "Elite · Lv … ", epitaph, stars and bar, Claimed / First / Where / Last |
| `feature-2-raids.png` | **Raids** tab, a partly claimed raid selected (Molten Core is ideal) | The Barrow Deeps and Hyjal Summit at the top ("TBD" or "N / ?"), `? ? ?` rows, boss skulls, progress bars under each raid |
| `feature-2-raids.png` (extra) | Raids tab with **The Barrow Deeps** selected | "Roster still sealed: 8 bosses wait inside…" note |
| `feature-3-catch.png` | The popup right after draining an **elite, rare or boss** (or `/dex test` for a sample Hogger) | Popup coloured by rarity with your rank emblem, "ELITE SOUL CLAIMED", "+5 PTS" |
| `feature-3-catch.png` | The **RANK UP** popup, if you cross a rank while shooting | Fel-green popup under the soul's: "Rank N of 8 · next: …" |
| `feature-3-catch.png` | Hover a named **Soul Shard** in your bags | Tooltip title "Soul of <name>", zone and date below |
| `feature-4-players-friends.png` | **Players** tab with a class selected; then **Friends** with a guildie selected | Class-coloured list; the friend's rank, score and "Browse dex" |
| `feature-5-me-milestones.png` | **Me** tab; then **Milestones** with one group's earned rows folded | Rank emblem crest, score bar, six tiles, records; milestone progress bars |
| `feature-6-settings.png` | `/dex options` with Window set to 120% | The six switches, SIZE with "Reset", Test popup / Reset window |
| `feature-6-settings.png` | Hover SoulDex in the addon list by the minimap | Tooltip "SoulDex v1.4.0", "<rank> · <score> pts", "Click to open. Right-click for options." |
| `feature-6-settings.png` | Type `/dex help` | "commands:" and the ten command lines, each starting "SoulDex" |
| (optional) | Esc > Options > AddOns > SoulDex | The same switches on the game's own Settings page |

Once you have the screenshots, either upload them to the gallery in place of the
mockups, or drop them into the HTML pages in `source/` and re-render, so the page keeps
its frame and captions. Remove the "Illustration" note from any image that becomes a
real screenshot.
