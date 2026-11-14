#!/usr/bin/env bash
# Renders the CurseForge images from the HTML sources in this folder with headless
# Chrome (or Edge). Run from anywhere in Git Bash: docs/curseforge/source/render.sh
# Output goes to docs/curseforge/images/.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
out="$here/../images"
mkdir -p "$out"

browser=""
for candidate in \
	"/c/Program Files/Google/Chrome/Application/chrome.exe" \
	"/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe" \
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

# file:/// URL for a page in this folder (Windows paths via cygpath when available).
url() {
	local path="$here/$1"
	if command -v cygpath >/dev/null 2>&1; then
		path="$(cygpath -m "$path")"
	fi
	echo "file:///$path${2:-}"
}

# shoot <page> <query> <width> <height> <output name>
shoot() {
	local target="$out/$5"
	if command -v cygpath >/dev/null 2>&1; then
		target="$(cygpath -w "$target")"
	fi
	"$browser" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
		--default-background-color=00000000 --allow-file-access-from-files \
		--window-size="$3,$4" --screenshot="$target" "$(url "$1" "$2")" >/dev/null 2>&1
	echo "  $5 (${3}x${4})"
}

echo "Rendering into $out"
shoot logo.html "?s=400" 400 400 logo-400.png
shoot logo.html "?s=800" 800 800 logo-800.png
shoot logo.html "?mark&s=256" 256 256 icon-256.png
shoot logo.html "?mark&s=64" 64 64 icon-64.png
shoot banner.html "" 1200 400 banner-1200x400.png
for page in 1-mobs 2-raids 3-catch 4-players-friends 5-me-milestones; do
	shoot "feature-$page.html" "" 1280 720 "feature-$page.png"
done
