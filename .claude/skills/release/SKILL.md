---
name: release
description: Cut a SoulDex release. Writes the CHANGELOG section and the release intro, commits, tags v<version> and pushes so the release workflow builds the zip.
disable-model-invocation: true
---

Argument: the new version, e.g. `1.3.0` (SemVer). Ask for it if it is missing.

1. Be on `main` with a clean tree, up to date with `origin/main`. If not, stop and ask.
2. Run `luacheck .` and `busted`. Both must pass.
3. `CHANGELOG.md`: rename `## [Unreleased]` to `## [<version>] - <today>` and put
   a fresh empty `## [Unreleased]` above it. Keep the section short: a few plain
   lines for players, not a list of every fix. The release page shows the whole file.
4. Rewrite `.github/release-intro.md` for this version. The release workflow
   (`scripts/release-intro.sh`) puts it on top of the release page, and leaves it
   out with a warning unless the first line names the version:
   `## 💜 SoulDex <version>: <title>`. Keep it short and readable for players:
   - a one-line warlock-flavoured tagline in italics,
   - **What's new** in 3–5 bold-led bullets,
   - install steps; say a full game restart is needed when the release adds a
     file to `SoulDex.toc`, otherwise `/reload` is enough,
   - a flavoured sign-off.
5. Show the user the CHANGELOG section and the intro, and wait for approval.
6. Commit as `chore: release <version>`, tag `v<version>`, push `main` and the tag.
   CI publishes from the tag; never upload a zip by hand from here.
7. Check the run with `gh run list --limit 3` and wait for it to finish
   (`gh run watch <id> --exit-status`).
8. Save the published zip locally: `gh release download v<version> -p '*.zip' -D releases --clobber`.
   `releases/` is git-ignored; it holds the exact zip from the GitHub release. The
   workflow uploads the same zip to CurseForge (needs the `CF_API_KEY` repo secret;
   a tag with "alpha" or "beta" in its name is a GitHub pre-release only),
   so this copy is a backup. Report the release URL and the local zip path.
