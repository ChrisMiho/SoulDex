# Submitting SoulDex to CurseForge

Everything for the CurseForge project page is in this folder. `docs/` is already in the
`.pkgmeta` ignore list, so none of it ends up in the addon zip.

| File | Use it for |
|------|-----------|
| `images/logo-400.png` | Project **avatar / logo** (square). `logo-800.png` if a bigger one is asked for |
| `images/icon-256.png`, `icon-64.png` | Same mark without the word, for places where text would be too small |
| `images/banner-1200x400.png` | Header image at the top of the description |
| `images/feature-1-mobs.png` … `feature-5-me-milestones.png` | **Images** tab (gallery), 1280×720 |
| `description.md` | Project **description** |
| `source/` | HTML the images are made from. Edit, then run `docs/curseforge/source/render.sh` (Git Bash on Windows) |

## 1. Before you start

- [ ] Sign in at <https://www.curseforge.com> and open the author console
  (<https://authors.curseforge.com>). Accept the author terms if it is your first project.
- [ ] Get the zip you will upload: every release saves the GitHub release zip to
  `releases/SoulDex-v<version>-forever.zip` (git-ignored). For an older release, run
  `gh release download v<version> -p '*.zip' -D releases`.

## 2. Create the project

Author console → **Create Project** → game **World of Warcraft** → class **Addons**.

| Field | Fill in |
|-------|---------|
| Project name | `SoulDex` |
| Summary | `Their souls. Your collection. Every Soul Shard becomes a trophy: claim mobs, players and raid bosses, and earn ranks.` (117 characters) |
| Short alternative | `Their souls. Your collection. Turns every Soul Shard into a trophy.` |
| Main category | **Class** (subcategory **Warlock** if offered) |
| Extra categories | **Achievements** (collection/points), **Minigames** |
| Logo / avatar | `images/logo-400.png` |
| Licence | **GNU General Public License version 3 (GPLv3)** |
| Description | paste `description.md` (Markdown editor), see step 3 |
| Source / Issues links | `https://github.com/ChrisMiho/SoulDex` and `https://github.com/ChrisMiho/SoulDex/issues` |
| Allow comments | on |

CurseForge reviews every new project by hand; that can take a few days.

## 3. Description

1. Upload the banner and the five `feature-*.png` images on the Media tab, and copy each
   one's URL.
2. In `description.md`, replace the placeholders with those URLs: `BANNER_IMAGE_URL`,
   `MOBS_IMAGE_URL` (feature 1), `RAIDS_IMAGE_URL` (2), `TOOLTIP_IMAGE_URL` (3),
   `FRIENDS_IMAGE_URL` (4), `ME_IMAGE_URL` (5).
3. Paste the whole file into the description, with the editor set to **Markdown**. If the
   project only offers the WYSIWYG editor, paste it into a Markdown previewer first
   (e.g. VS Code preview) and copy the rendered text across.

## 4. Images tab

Upload the five `feature-*.png` files, in order, with these titles:

1. **The hunt** — Every kill a trophy
2. **The raids** — Drain every raid
3. **The trophies** — Every shard has a name
4. **The rivals** — Hunt players. Outrank friends.
5. **The climb** — Rise through the ranks

These are drawn illustrations of the window, built from the addon's own colours and
labels (each one says "Illustration" in the corner). **Add real in-game screenshots as
soon as you can**; players trust them more. Good ones to take:

- [ ] The window on the Mobs tab with a detail pane open (an elite or rare).
- [ ] The Raids tab with a partly claimed raid, showing `? ? ?` and boss skulls.
- [ ] The SOUL CLAIMED popup right after a claim (an elite or a boss shows its colour).
- [ ] A named Soul Shard's tooltip in your bags (title "Soul of …").
- [ ] The Friends tab with at least one guildie listed.
- [ ] The Me tab, showing your rank and its progress bar.

Hide other UI clutter (Alt+Z hides the whole UI, so open the window first and crop).

## 5. Upload the first file

Files tab → **Upload File**:

| Field | Fill in |
|-------|---------|
| File | the `SoulDex-v<version>-forever.zip` zip |
| Display name | `SoulDex <version>` |
| Release type | **Release** |
| Game version | **Forever** (1.60.1 / interface 16001; tick every Forever version listed) |
| Changelog | that version's lines from `CHANGELOG.md` (Markdown) |
| Related projects | **Ace3**: *Embedded library* (LibStub, CallbackHandler and AceComm are bundled) |

The zip must contain one top-level `SoulDex/` folder; the packager already does this.

## Updating the page after the rebrand

The images and `description.md` were redone for the "Their souls. Your collection." branding, and they
show things that arrive with the release after 1.2.4 (ranks, named milestones, progress
bars, the coloured popup). Release that version first, then:

1. Project settings: replace the **logo** with `images/logo-400.png` and the **summary**
   with the one in step 2.
2. Media tab: upload the new banner and the five `feature-*.png` files. Delete the old ones.
3. `description.md` still points at the first uploads' URLs: replace each
   `https://media.forgecdn.net/...` link with the new upload's URL, then paste the file
   into the description.
4. Images tab: replace the five gallery images and their titles (step 4 above).

## Brand

- **Voice:** a soul hunter's. Souls are *claimed*, a claim is a *trophy*, the player
  *hunts*, *drains* and *outranks*. Dry and confident, never sentimental.
- **Lines:** "Their souls. Your collection." (the user picked it) and "Hunt. Drain. Claim."
- **Colours:** near-black `#030205`, shadow purple `#8a5cd0`, black iron `#2b2437` and fel
  green `#8dff3a`. No gold: the user asked for it darker and more demonic.
- **Type:** Cinzel capitals for headlines (`source/fonts/`, SIL Open Font License); the
  wordmark is cold iron-violet, accents burn fel green.
- **Emblem:** a soul shard crackling with fel-green energy (jagged bolts and sparks), held in a
  spiked ring of black iron (`source/shard.svg`). No horns and no fire. The
  summoning circle behind the artwork is `source/sigil.svg`.

## Licence

SoulDex is GPLv3, in the repo (`LICENSE`) and on CurseForge. It has to be: the zip ships
`src/RaidData.lua`, which is derived from Questie (GPL-3).

## Trademarks

The page, the README and the `.toc` `## Notes` call SoulDex a collection dex and never
use Pokémon names or art. Keep it that way: CurseForge moderators may reject a project
that uses another company's trademarks or art.

## 6. Automatic uploads

The project is approved (Project ID 1806215), and the release workflow uploads to
CurseForge by itself: on each `v*` tag the BigWigs packager builds the zip, attaches it
to the GitHub release and sends the same zip to CurseForge. A tag with "alpha" or "beta"
in its name (such as `v1.3.0-beta.1`) goes up as an alpha or beta file.

It needs two things:

- `## X-Curse-Project-ID: 1806215` in `SoulDex.toc` (already there; the ID is public).
- The repo secret `CF_API_KEY`: an API token made at
  <https://authors.curseforge.com/account/api-tokens>, stored under Settings → Secrets
  and variables → Actions on GitHub. The token lives only there: never in a file in the
  repo, git-ignored or not. Without it the CurseForge upload is skipped and the GitHub
  release is still made.

After the first automatic upload, check it on the Files tab. If it isn't tagged with the
Forever game version, set it by hand and give the packager the version in
`.github/workflows/release.yml` with `with: { args: -g <game version> }`, using the
version CurseForge shows for Forever.

The page text and images are not uploaded automatically: update them by hand from
`description.md` and `images/`.
