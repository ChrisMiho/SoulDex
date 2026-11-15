#!/usr/bin/env bash
# Renders the rank emblems from emblem.html with headless Chrome (or Edge) and turns them
# into the game's textures. Run from anywhere (Git Bash on Windows): scripts/art/render.sh
# Output: art/rank1.tga .. art/rank8.tga and docs/curseforge/images/rank-emblems.png.
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

for rank in 1 2 3 4 5 6 7 8; do
	shoot "?rank=$rank" 256 256 "$tmp/rank$rank.png"
	"$python" "$here/to_tga.py" "$tmp/rank$rank.png" "$root/art/rank$rank.tga"
	echo "  art/rank$rank.tga"
done
shoot "?sheet" 1200 420 "$root/docs/curseforge/images/rank-emblems.png"
echo "  docs/curseforge/images/rank-emblems.png"
