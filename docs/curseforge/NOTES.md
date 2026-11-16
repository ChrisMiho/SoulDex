# CurseForge page refresh for 1.4.0

What changed on the page, which images are drawn, and the in-game screenshots that
should replace them. Upload steps are in `SUBMISSION.md`.

## What changed

- `description.md`
  - Intro: open with `/dex`, a key binding or the addon list by the minimap.
  - The hunt: dungeon souls get their real names (a boss drained mid-fight is still
    Unknown). How SoulDex reads them is deliberately left off the page.
  - The raids: The Barrow Deeps and Hyjal Summit are listed, rosters still to come.
  - The trophies: points on the popup; mastery stars and rank-ups get their own popups.
  - The climb: rank emblems, milestones from First Harvest to Raid Reaper, the Me tab's
    records.
  - New section, **The grimoire** (text only, no image): the switches in plain words,
    SIZE (60–160%), the Settings > AddOns page and the key binding.
  - Commands table: every command `/dex help` lists (`src/Init.lua`), and a pointer to `/dex help`.
  - Removed the "How claiming works on WoW: Forever" section (and with it the
    experimental option and the Classic Era raid-data note).
  - Image links 1–5 point at the new uploads (attachments 2219/36–40), since
    all five images are new uploads. The banner keeps its current URL (unchanged).
- `README.md`: the same additions.
- `source/`: the window, popup and Me crest icons now show the real rank emblem
  (`scripts/art/emblem.html`, the art `art/rank<N>.tga` is made from) instead of a
  purple placeholder; Forever's raids are on the Raids list. Logo, icons and banner are unchanged.

## Real or mockup

No image is an in-game screenshot. All five feature images are **mockups**, drawn in
HTML from the layout and colours in `src/UI*.lua`, `src/Toast.lua`, `src/Options.lua`
and `src/Init.lua`, and each says "Illustration" in its corner. The banner, logo, icons
and `rank-emblems.png` are brand art, not the UI.

Places where a mockup is only an approximation:

- Fonts: the game's own font is drawn as a serif (window) or Arial (chat).
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
| (optional) | Esc > Options > AddOns > SoulDex | The same switches on the game's own Settings page |

Once you have the screenshots, either upload them to the gallery in place of the
mockups, or drop them into the HTML pages in `source/` and re-render, so the page keeps
its frame and captions. Remove the "Illustration" note from any image that becomes a
real screenshot.
