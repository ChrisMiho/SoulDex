# SoulDex colour themes: design

## Intent

Players want to make the dex window their own. Four warlock-flavoured colour themes, picked
in the options, saved per character, applied at once (no /reload). Soul Shard (today's look)
is the branding theme and the default. Each theme is its own whole look: its chrome, its
text tones, its accent (today's fel green) and its own set of rank emblems.

## Goals, non-goals

- Goals: four themes; a picker on the options panel and the game's Settings page; every
  window surface (title bar, tabs, lists, trophy card, Me tab, Friends tab, options panel,
  new-soul and rank-up popups) and the rank emblems follow the theme and repaint the moment
  it changes.
- Non-goals: custom colours, per-surface choices, theming chat lines, the game tooltip, or
  the CurseForge page.
- Anti-goals: a theme that changes what a colour *means* in a list. Rarity colours (elite
  gold, rare silver, boss orange) and class colours stay fixed in every theme. A theme that
  leaves a stray purple control behind is a bug.

## Approaches

1. **Colour table plus a repaint list (picked).** A pure `Themes` module holds each theme's
   colours under shared slot names. The painting helpers in `UIList.lua` take a slot name,
   paint it, and remember the object and slot (weak-keyed); a theme change refills the
   shared colour table and repaints everything remembered, then refreshes the window. List
   rows already repaint on every refresh. One mechanism; a control added later follows by
   itself as long as it is painted by slot name.
2. A `repaint()` per file (UI, UIDetail, Toast, Net, Options). Less change to the helpers,
   but more code and easy to miss a control. Not picked.
3. Apply on /reload only. Ruled out: the theme should change at once.

Emblems:

1. **A rendered set per theme (picked).** `emblem.html` takes `?theme=<id>` and recolours its
   two colour families (the violet shard and glow, the fel bolts and aura) to the theme's
   main and accent hues. `render.sh` draws `art/rank<N>.tga` for Soul Shard (unchanged
   paths) and `art/<id>/rank<N>.tga` for the others, plus one review sheet per theme.
2. Tinting the existing emblems in game (`SetVertexColor`). Ruled out: multiplying colours
   muddies them (purple times orange is brown).

## The themes

Theme ids (saved) and names (shown): `soulshard` "Soul Shard", `fel` "Fel", `shadow`
"Shadow", `ember` "Ember". The picker shows them in that order.

Slots (every theme defines every slot; hex `rrggbb`):

| Slot | Used for | Soul Shard | Fel | Shadow | Ember |
|------|----------|-----------|-----|--------|-------|
| TEXT | ordinary text | e8e0f0 | e4f0dc | e0e0f5 | f2e4dc |
| WHITE | emphasis | ffffff | ffffff | ffffff | ffffff |
| TITLE | title, buttons | c9a8ff | b8f07a | a9b4ff | ffb08a |
| MUTED | secondary text | 9a8fb0 | 94a886 | 8c8cb0 | b09a8f |
| HEADER | section heads, card edge | 8a72b8 | 76a050 | 6e74b8 | c06a50 |
| UNKNOWN | not-yet-caught names | 4d4360 | 3e4d34 | 3e3e5c | 5c3e36 |
| DIM | offline, done goals | 6e6385 | 66785a | 5f5f85 | 85665c |
| FLAVOUR | the card's quote | b9a6d9 | a9c890 | a3a8d9 | d9b4a3 |
| GOOD | new, done, score, progress fill | 7dff6a | 7dff6a | 8ad8ff | ffe9a8 |
| ACCENT | rank, mastery stars, selected marker, tab underline | 9dff3a | ccff33 | c18cff | ff7a1a |
| BG | window, popup, options panel | 14101c | 0f140b | 0c0c18 | 160d0b |
| PANE_BG | trophy card, Friends panes | 0d0a14 | 0a0e07 | 08080f | 0e0807 |
| SHADE_TOP | window shading, top | 241835 | 1a2612 | 181a33 | 2e1410 |
| SHADE_BOTTOM | window shading, bottom | 0b0812 | 060904 | 050509 | 090504 |
| BORDER | window and popup border, scroll thumb | 6b4fa0 | 4f8a2a | 4b4a8f | 9a3022 |
| DIVIDER | dividers, rules, stripe, button hover | 3d2d5c | 2d4a1c | 2a2a52 | 4f1d16 |
| TAB_BG | tabs, buttons | 251b36 | 1a2a12 | 17172e | 2a1410 |
| BUTTON_EDGE | button border | 5a4486 | 437a24 | 3f3e7a | 7f2a1d |
| TRACK | bar tracks, row rule | 2d2240 | 22351a | 1f1f3d | 351a14 |
| SELECTED | selected row | 3a2a55 | 2c4a1e | 2a2a55 | 52221a |
| HOVER | hovered row | 2a2040 | 1f3216 | 1c1c38 | 3a1913 |
| ROW_LINE | line under a row | 1d1629 | 141f0e | 121224 | 1f100c |
| TILE_BG | Me tiles, card cells | 151020 | 111a0c | 0f0f1f | 1a0f0c |
| TILE_EDGE | their border | 231a35 | 1e2e15 | 1c1c36 | 301a14 |
| QUOTE_BAR | bar beside the quote | 4a3470 | 3a6324 | 34336b | 6b2a1c |
| CHIP_BG | rank chip, card badge | 0a1404 | 0a1404 | 120f26 | 1f0e04 |
| CHIP_EDGE | their border | 3d6b1f | 5f8f1f | 4a3d8f | 7a3d12 |

Soul Shard's values are today's, so the default look does not change. `ELITE`, `RARE`,
`BOSS` stay in the colour table from `ns.Rarity`, the same in every theme.

Emblem hues (for `emblem.html`): Soul Shard as drawn today; Fel: main green, accent
yellow-green; Shadow: main indigo, accent pale violet; Ember: main blood red, accent orange.

## How it works

- **`src/Themes.lua`** (pure, busted-tested): `Themes.LIST` (ordered `{ id, name }`),
  `Themes.DEFAULT = "soulshard"`, `Themes.id(value)` (a known id, else the default),
  `Themes.palette(id)` (the slot table, the default's for an unknown id),
  `Themes.name(id)`, `Themes.next(id, by)` (the picker's step, wrapping round),
  `Themes.emblemDir(id)` (`""` for Soul Shard, `"<id>\\"` otherwise). Loaded before
  `Settings.lua` and `UIFormat.lua` in the `.toc`.
- **Setting:** `settings.theme`, default `"soulshard"`; `Settings.normalise` keeps it only
  when `Themes.id` knows it.
- **`UIFormat.COLORS`** stays the one table every file reads; it is filled from the active
  palette (plus the fixed rarity colours) and refilled in place on a change. `GREEN` and
  `FEL` are renamed `GOOD` and `ACCENT` (and `View`'s `color = "FEL"` keys with them),
  since in Ember they are not green. The mastery star's tint (`F.MARKS.FEL_STAR`, renamed
  `ACCENT_STAR`) is built from `ACCENT`.
- **Painting helpers** (`UIList.lua`): `textColor`, `fill`, `gradient`, `backdrop` accept a
  slot name or a hex value. A slot name is resolved through `COLORS` and the object is
  remembered with its slot(s); a hex value paints and forgets any remembered slot.
  `L.repaint()` repaints everything remembered. Every local hex constant in `UI`, `UIList`,
  `UIDetail`, `Toast`, `Net` and `Options` becomes a slot name.
- **`ns.UI.setTheme(id)`** (game code): saves the id, refills `COLORS`, `L.repaint()`, then
  refreshes the window, the open trophy card, the Friends tab, the options and the popups'
  standing colours. Called by the picker; at login the saved theme is applied before any
  frame is built.
- **`Ranks.emblem(index, theme)`**: the path under `art\` plus `Themes.emblemDir`. Callers
  pass the active theme; the title bar, crest and card icons are set on refresh, so they
  follow.
- **Options:** a THEME section above SIZE: the label "Theme", then `<  Soul Shard  >`
  (the existing - / + stepper buttons, wrapping round). Both the panel and the Settings page
  get it, kept in step by `sync()`. Changing it shows a silent sample popup, like the Popup
  size row.

## Constraints

- Lua 5.1, pure modules call no WoW API; `.luacheckrc` stays in step.
- `spec/Art_spec.lua` checks every theme's emblem set (64x64 32-bit TGA, transparent corner).
- `render.sh` needs Pillow (`pip install pillow`, agreed).
- Another session is editing `Options.ITEMS`, `Settings.DEFAULTS` and the spec's settings
  list at the same time; merge by hand.

## Left to the builder

- The exact recolour maths in `emblem.html`, judged by eye on the review sheets.
- Small palette tweaks if a value reads badly next to another in a sample render; the
  player-visible look is checked in game (spec section 9).
