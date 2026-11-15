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
| `source/` | HTML the images are made from. Edit, then run `docs/curseforge/source/render.sh` in Git Bash |

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
| Summary | `A collector's dex for warlocks: every Soul Shard records whose soul it holds. Catch mobs, players and raid souls.` (113 characters) |
| Short alternative | `Every Soul Shard remembers whose soul it holds. A collection game for warlocks.` |
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

1. **Mobs** — Every shard is a soul caught
2. **Raids** — Catch every raid soul
3. **Shard tooltip** — Your shards remember
4. **Players and Friends** — Players, and rivals
5. **Me and Milestones** — Score, stats and milestones

These are drawn illustrations of the window, built from the addon's own colours and
labels (each one says "Illustration" in the corner). **Add real in-game screenshots as
soon as you can**; players trust them more. Good ones to take:

- [ ] The window on the Mobs tab with a detail pane open (an elite or rare).
- [ ] The Raids tab with a partly caught raid, showing `? ? ?` and boss skulls.
- [ ] The NEW SOUL CAUGHT! popup right after a catch.
- [ ] A named Soul Shard's tooltip in your bags (title "Soul of …").
- [ ] The Friends tab with at least one guildie listed.

Hide other UI clutter (Alt+Z hides the whole UI, so open the window first and crop).

## 5. Upload the first file

Files tab → **Upload File**:

| Field | Fill in |
|-------|---------|
| File | the `SoulDex-v<version>` zip |
| Display name | `SoulDex <version>` |
| Release type | **Release** |
| Game version | **Forever** (1.60.1 / interface 16001; tick every Forever version listed) |
| Changelog | that version's lines from `CHANGELOG.md` (Markdown) |
| Related projects | **Ace3**: *Embedded library* (LibStub, CallbackHandler and AceComm are bundled) |

The zip must contain one top-level `SoulDex/` folder; the packager already does this.

## Licence

SoulDex is GPLv3, in the repo (`LICENSE`) and on CurseForge. It has to be: the zip ships
`src/RaidData.lua`, which is derived from Questie (GPL-3).

## Trademarks

The page, the README and the `.toc` `## Notes` call SoulDex a collection dex and never
use Pokémon names or art. Keep it that way: CurseForge moderators may reject a project
that uses another company's trademarks or art.

## 6. After approval: automatic uploads (optional)

The release workflow already runs the BigWigs packager on each `v*` tag. It can upload
to CurseForge too:

1. Note the **Project ID** on the project's page (right-hand "About Project" box).
2. Add it to `SoulDex.toc`, under `## Author`:
   `## X-Curse-Project-ID: <id>`
3. Create an API token at <https://authors.curseforge.com/account/api-tokens>, and add it
   to the GitHub repo as the secret `CF_API_KEY` (Settings → Secrets and variables → Actions).
4. In `.github/workflows/release.yml`, give the packager step the token:

   ```yaml
   - uses: BigWigsMods/packager@v2.6.1
     env:
       GITHUB_OAUTH: ${{ secrets.GITHUB_TOKEN }}
       CF_API_KEY: ${{ secrets.CF_API_KEY }}
   ```

5. Check the first automatic upload on the Files tab: if it isn't tagged with the
   Forever game version, set it by hand and add the version for the packager with
   `with: { args: -g <game version> }`, using the version CurseForge shows for Forever.

Do the first upload by hand (step 5) so the project exists and is approved before
automating it.
