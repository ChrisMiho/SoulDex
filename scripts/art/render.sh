#!/usr/bin/env bash
# Renders the rank emblems from emblem.html with headless Chrome (or Edge) and turns them
# into the game's textures. Run from anywhere (Git Bash on Windows): scripts/art/render.sh
# Output: art/rank1.tga .. art/rank8.tga, art/<theme>/rank1.tga .. rank8.tga for the other
# colour themes, docs/curseforge/images/rank-emblems.png and .release/emblem-sheets/.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
mkdir -p "$root/art" "$root/docs/curseforge/images"

browser=""
for candidate in \
	"/c/Program Files/Google/Chrome/Application/chrome.exe" \
	"/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe" \
	"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
	"$(command -v google-chrome || true)" \
	"$(command -v chromium || true)"; do
	if [ -n "$candidate" ] && [ -x "$candidate" ]; then
		browser="$candidate"
		break
	fi
done
if [ -z "$browser" ]; then
	echo "No Chrome or Edge found" >&2
	exit 1
fi

python=""
for candidate in python3 python; do
	if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c "import sys; sys.exit(sys.version_info[0] < 3)" 2>/dev/null; then
		python="$candidate"
		break
	fi
done
if [ -z "$python" ]; then
	echo "No Python 3 found" >&2
	exit 1
fi

# Windows paths via cygpath when available.
native() {
	if command -v cygpath >/dev/null 2>&1; then
		cygpath -w "$1"
	else
		echo "$1"
	fi
}

page="$here/emblem.html"
if command -v cygpath >/dev/null 2>&1; then
	page="$(cygpath -m "$page")"
fi

# shoot <query> <width> <height> <output file>
shoot() {
	rm -f "$4"
	"$browser" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
		--default-background-color=00000000 --allow-file-access-from-files \
		--window-size="$2,$3" --screenshot="$(native "$4")" "file:///${page#/}$1" >/dev/null 2>&1 || true
	if [ ! -s "$4" ]; then
		echo "screenshot failed: $(basename "$4")" >&2
		exit 1
	fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Soul Shard (the branding theme) at the top of art/, every other theme in its own folder
# (the ids of src/Themes.lua). Soul Shard's review sheet is the CurseForge image; the
# others' go to .release/emblem-sheets/ (git-ignored) for a look.
for theme in soulshard fel shadow ember; do
	if [ "$theme" = soulshard ]; then
		dir="$root/art"
		sheet="$root/docs/curseforge/images/rank-emblems.png"
	else
		dir="$root/art/$theme"
		sheet="$root/.release/emblem-sheets/rank-emblems-$theme.png"
	fi
	mkdir -p "$dir" "$(dirname "$sheet")"
	for rank in 1 2 3 4 5 6 7 8; do
		shoot "?rank=$rank&theme=$theme" 256 256 "$tmp/rank$rank.png"
		"$python" "$here/to_tga.py" "$tmp/rank$rank.png" "$dir/rank$rank.tga"
		echo "  ${dir#"$root/"}/rank$rank.tga"
	done
	shoot "?sheet&theme=$theme" 1200 420 "$sheet"
	echo "  ${sheet#"$root/"}"
done
