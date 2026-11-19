#!/bin/sh
# Build dist/minimalhome-<version>.zip, ready to unzip into koreader/plugins/.
# Every build raises the patch number in _meta.lua first (0.1.0 → 0.1.1), so the
# zip name and the version shown in Settings always match.
# Usage: tools/package.sh            bump, then build
#        tools/package.sh --no-bump  build the current version (release CI)
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
META="$ROOT/minimalhome.koplugin/_meta.lua"
VERSION="$(sed -n 's/.*version = "\(.*\)".*/\1/p' "$META")"
if [ "${1:-}" != "--no-bump" ]; then
    VERSION="$(echo "$VERSION" | awk -F. '{ printf "%d.%d.%d", $1, $2, $3 + 1 }')"
    sed -i.bak "s/version = \"[^\"]*\"/version = \"$VERSION\"/" "$META" && rm -f "$META.bak"
fi
mkdir -p "$ROOT/dist"
OUT="$ROOT/dist/minimalhome-$VERSION.zip"
rm -f "$OUT"
cd "$ROOT"
zip -qr "$OUT" minimalhome.koplugin -x '*.DS_Store'
echo "$OUT"
