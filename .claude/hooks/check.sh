#!/usr/bin/env bash
# Stop hook: when Lua or lint/test config has uncommitted changes, run luacheck
# and busted; exit 2 (sends Claude back to work with the output) if either fails.
# Skips quietly when nothing relevant changed or the tools are not installed.
cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}" || exit 0

changed="$(git status --porcelain -- '*.lua' '*.toc' .luacheckrc .busted 2>/dev/null)"
[ -n "$changed" ] || exit 0

if ! command -v luacheck >/dev/null 2>&1 || ! command -v busted >/dev/null 2>&1; then
	exit 0
fi

out="$(luacheck . --no-color -q 2>&1)" || {
	echo "luacheck failed:" >&2
	echo "$out" >&2
	exit 2
}
out="$(busted -o utfTerminal 2>&1)" || {
	echo "busted failed:" >&2
	echo "$out" | tail -60 >&2
	exit 2
}
exit 0
