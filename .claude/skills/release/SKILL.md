---
name: release
description: Cut a SoulDex alpha, beta or release. Works out the version number, checks the stage's conditions, writes the changelog and release intro, commits, tags v<version> and pushes so the release workflow builds and publishes the zip.
disable-model-invocation: true
---

Argument: the stage, `alpha`, `beta` or `release`. Ask for it if it is missing. You work
out the version number (below); the user does not keep track of it. A full version given
instead (`1.5.0-beta.2`) is used as it is.

The tag's name alone decides where the zip goes (`.github/workflows/release.yml`):

| Stage | Tag | Goes to | Cut it when |
|---|---|---|---|
| alpha | `v1.5.0-alpha.N` | GitHub pre-release only | A zip is wanted that nobody has played yet |
| beta | `v1.5.0-beta.N` | GitHub pre-release and CurseForge beta channel | The user has played this code and the feature set is done |
| release | `v1.5.0` | GitHub and CurseForge, everyone | A beta survived real play with nothing new found |

Everyday testing needs no tag: `scripts/build.sh` builds and installs into the game.

**The rule behind the stages: nothing reaches CurseForge that the user has not played.**
Agents cannot run the game, so only the user can say a build was played. Never infer it.

## The version

Versions follow SemVer. Read the tags (`git tag --sort=-v:refname`): the last plain
`vX.Y.Z` is the last release; any `-alpha.N` / `-beta.N` tags above it belong to the
version in progress.

1. **The base version.** Judge the bump from what changed since the last release (the
   lines under `## [Unreleased]` in `CHANGELOG.md`, and `git log <last release>..HEAD`):
   - **major**: a player loses something on updating: saved data an older version wrote
     no longer loads, or the Friends wire format stops talking to the last release.
   - **minor**: anything new a player can see or use (a feature, an option, a command).
   - **patch**: fixes only.
   If a version is already in progress, keep its base, unless what was added since now
   calls for a bigger bump (a feature landed on what was a patch): then move to the
   bigger base and start its numbering again at 1.
2. **The suffix.** `alpha` and `beta`: one more than the highest N that stage has for the
   base, or 1. `release`: no suffix.
3. An alpha asked for when the base already has a beta would go backwards: say so and ask
   whether a beta was meant.

Say which version you chose and why, in one line, when you show the changelog and intro
for approval (step 4): the user can correct it there.

## Conditions, by stage

Stop and ask when one is not met.

- **alpha**: any branch, clean tree. No other condition.
- **beta**: any branch, clean tree. Ask the user to confirm they played this code (a local
  build or an alpha) and went through the in-game checks for what changed (section 9 of
  `docs/superpowers/specs/2026-11-10-souldex-design.md`). From beta.1 on, only fixes:
  if commits since the previous beta add a feature, say so and ask.
- **release**: on `main`, clean, up to date with `origin/main`. There must be a beta tag
  for this version, and the shipped files must not have changed since the last one:
  `git diff <last beta tag> -- src art SoulDex.toc Bindings.xml embeds.xml .pkgmeta`
  prints nothing. If it prints something, the code was never in a beta: propose another
  beta instead.

## Steps

1. Run `luacheck .` and `busted`. Both must pass.
2. `CHANGELOG.md`:
   - alpha and beta: leave the lines under `## [Unreleased]`; check each user-facing
     change has one.
   - release: rename `## [Unreleased]` to `## [<version>] - <today>` and put a fresh
     empty `## [Unreleased]` above it. Keep the section short: a few plain lines for
     players, not a list of every fix. The release page shows the whole file.
3. Rewrite `.github/release-intro.md` for this version. `scripts/release-intro.sh` puts
   it on top of the release page, and leaves it out with a warning unless the first line
   names the version: `## 💜 SoulDex <version>: <title>`. Keep it short and readable for
   players:
   - a one-line warlock-flavoured tagline in italics (an alpha or beta says it is a test
     build, and an alpha that nothing in it has been seen in game),
   - **What's new** in 3–5 bold-led bullets,
   - install steps; say a full game restart is needed when the build adds a file to
     `SoulDex.toc`, otherwise `/reload` is enough,
   - a flavoured sign-off.
4. Show the user the changelog section and the intro, and wait for approval.
5. Commit (`chore: release <version>`), tag `v<version>`, push the branch and the tag.
   CI publishes from the tag; never upload a zip by hand.
6. Wait for the run: `gh run list --workflow release.yml --limit 1`, then
   `gh run watch <id> --exit-status`.
7. Check where it went, from the run itself, and report it:
   `gh run view <id> --json jobs -q '.jobs[].steps[] | "\(.name): \(.conclusion)"'`
   - alpha: "Package an alpha" succeeded and "Package a beta or a release" was
     **skipped**, and `gh run view <id> --log | grep -i curseforge` shows no upload.
     Anything else means it went to CurseForge: tell the user at once.
   - beta and release: the log has "Uploading ... to https://wow.curseforge.com" and
     "Success!".
8. Save the published zip: `gh release download v<version> -p '*.zip' -D releases --clobber`
   (`releases/` is git-ignored). Report the release URL and the local zip path.
