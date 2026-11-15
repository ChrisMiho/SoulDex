#!/usr/bin/env bash
# Build the addon exactly as a release would, then:
#   1. zip it as .release/SoulDex-<version>.zip (one SoulDex/
#      folder inside, ready to unzip into Interface\AddOns), and
#   2. install it into your game's AddOns folder.
#
# Usage:  scripts/build.sh               build, zip, install
#         scripts/build.sh --no-install  build and zip only
#
# Works in Git Bash on Windows and in a terminal on macOS or Linux. This script
# itself runs on any bash, including the old 3.2 that macOS ships; the packager
# needs 4.3 or newer, so one is looked for below (macOS: "brew install bash").
#
# The AddOns folder defaults to the standard Forever install for this system.
# Override it with the WOW_ADDONS_DIR environment variable. When the variable
# is not set and the standard folder is not there (the game is on another
# machine), the install step is skipped and only the zip is made.
set -euo pipefail

PACKAGER_VERSION="v2.6.1" # keep in step with .github/workflows/release.yml
ADDON="SoulDex"

case "$(uname -s)" in
	Darwin) DEFAULT_ADDONS_DIR="/Applications/World of Warcraft/_forever_/Interface/AddOns" ;;
	MINGW* | MSYS* | CYGWIN*) DEFAULT_ADDONS_DIR="/c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns" ;;
	*) DEFAULT_ADDONS_DIR="" ;;
esac

install=1
for arg in "$@"; do
	case "$arg" in
		--no-install) install=0 ;;
		*) echo "Unknown option: $arg" >&2; exit 2 ;;
	esac
done

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

# --- A bash new enough for the packager (4.3+) --------------------------------
new_enough() {
	"$1" -c '[ "${BASH_VERSINFO[0]}" -gt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -ge 3 ]; }' 2> /dev/null
}
packager_bash=""
# The bash running this script, then Homebrew's (Apple silicon, Intel), then PATH.
for candidate in "$BASH" /opt/homebrew/bin/bash /usr/local/bin/bash "$(command -v bash || true)"; do
	if [ -n "$candidate" ] && [ -x "$candidate" ] && new_enough "$candidate"; then
		packager_bash="$candidate"
		break
	fi
done
if [ -z "$packager_bash" ]; then
	echo "The packager needs bash 4.3 or newer; this one is $BASH_VERSION." >&2
	echo "On macOS, install one with: brew install bash" >&2
	exit 1
fi

# --- Packager (pinned) -------------------------------------------------------
mkdir -p .release
packager=".release/release.sh"
if [ ! -f "$packager" ] || [ "$(cat .release/.packager-version 2>/dev/null)" != "$PACKAGER_VERSION" ]; then
	echo "Downloading packager $PACKAGER_VERSION"
	curl -fsSL "https://raw.githubusercontent.com/BigWigsMods/packager/$PACKAGER_VERSION/release.sh" -o "$packager"
	echo "$PACKAGER_VERSION" > .release/.packager-version
fi

# The packager skips files git does not know about. Edits to tracked files are
# included; brand-new files need "git add" first.
untracked="$(git ls-files --others --exclude-standard)"
if [ -n "$untracked" ]; then
	echo "Warning: these new files are NOT in the build until you git add them:"
	echo "$untracked" | sed 's/^/  /'
fi

# -d: no upload. -z: we zip ourselves below, since Git Bash has no zip tool.
echo "Packaging..."
"$packager_bash" "$packager" -d -z > .release/packager.log 2>&1 || {
	cat .release/packager.log
	echo "Packaging failed" >&2
	exit 1
}

pkg=".release/$ADDON"
version="$(sed -n 's/^## Version: *//p' "$pkg/$ADDON.toc" | tr -d '\r')"
[ -n "$version" ] || { echo "Could not read version from $pkg/$ADDON.toc" >&2; exit 1; }

# --- Zip ---------------------------------------------------------------------
zipfile=".release/$ADDON-$version.zip"
rm -f "$zipfile"
if command -v zip > /dev/null 2>&1; then
	(cd .release && zip -qr "$(basename "$zipfile")" "$ADDON")
elif [ -x /c/Windows/System32/tar.exe ]; then
	# Windows' own tar (bsdtar) writes standard zip files with -a
	/c/Windows/System32/tar.exe -a -c -f "$zipfile" -C .release "$ADDON"
else
	echo "No zip tool found (need zip, or Windows tar.exe)" >&2
	exit 1
fi
echo "Zip:     $root/$zipfile"

# --- Install -----------------------------------------------------------------
if [ "$install" -eq 1 ]; then
	addons_dir="${WOW_ADDONS_DIR:-$DEFAULT_ADDONS_DIR}"
	if [ -n "${WOW_ADDONS_DIR:-}" ] && [ ! -d "$addons_dir" ]; then
		echo "AddOns folder not found: $addons_dir" >&2
		echo "Fix WOW_ADDONS_DIR, or use --no-install." >&2
		exit 1
	fi
	if [ ! -d "$addons_dir" ]; then
		echo "Install: skipped, no game folder found here${addons_dir:+ ($addons_dir)}."
		echo "         Copy the zip to the machine with the game, or set WOW_ADDONS_DIR."
		install=0
	fi
fi
if [ "$install" -eq 1 ]; then
	target="$addons_dir/$ADDON"
	if [ -L "$target" ]; then
		echo "Refusing to install: $target is a link. Remove the link first." >&2
		exit 1
	fi
	rm -rf "$target"
	cp -r "$pkg" "$target"
	echo "Install: $target"
	echo "In game, type /reload to load the new build."
fi

echo "Built $ADDON $version"
