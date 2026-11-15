#!/usr/bin/env bash
# Puts .github/release-intro.md at the top of a tag's GitHub release, above the
# changelog the packager wrote. Run by .github/workflows/release.yml after the
# packager; needs the gh CLI and GH_TOKEN.
#
# Usage: scripts/release-intro.sh v1.2.0
#
# The intro's first line must name the version (for example
# "## SoulDex 1.2.0: ..."). An intro for another version is left out with a
# warning, so a forgotten update never posts last release's text. Running it
# twice doesn't add the intro twice.
set -euo pipefail

tag="${1:?usage: scripts/release-intro.sh <tag>}"
version="${tag#v}"
intro="${RELEASE_INTRO:-.github/release-intro.md}"

if [ ! -s "$intro" ]; then
	echo "::warning::No $intro: release notes left as the packager wrote them."
	exit 0
fi

first="$(head -n 1 "$intro" | tr -d '\r')"
# -w: "1.2.0" must not match inside "11.2.0" or "1.2.01".
if ! printf '%s\n' "$first" | grep -qwF -- "$version"; then
	echo "::warning::$intro is not for $version (its first line: \"$first\"). Left out; update it for the next release."
	exit 0
fi

body="$(gh release view "$tag" --json body -q .body)"
if [ "$(printf '%s\n' "$body" | head -n 1 | tr -d '\r')" = "$first" ]; then
	echo "The intro is already at the top of $tag."
	exit 0
fi

notes="$(mktemp)"
trap 'rm -f "$notes"' EXIT
{
	tr -d '\r' < "$intro"
	printf '\n---\n\n'
	printf '%s\n' "$body"
} > "$notes"
gh release edit "$tag" --notes-file "$notes" > /dev/null
echo "Added $intro to the top of $tag."
